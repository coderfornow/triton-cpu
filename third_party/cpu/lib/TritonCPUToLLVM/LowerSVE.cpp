#include "cpu/include/TritonCPUToLLVM/Passes.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"

#include "triton/Dialect/Triton/IR/Dialect.h"

namespace mlir::triton::cpu {
#define GEN_PASS_DEF_LOWERSVE
#include "cpu/include/TritonCPUToLLVM/Passes.h.inc"
} // namespace mlir::triton::cpu

using namespace mlir;

namespace {

/// Lower a leading-dimension add reduction over pairs of elements. Loading
/// pairs and deinterleaving them in scalable registers avoids materializing a
/// fixed number of extracts and scalar combines.
struct LowerOuterReduction
    : public OpRewritePattern<vector::MultiDimReductionOp> {
  using OpRewritePattern::OpRewritePattern;

  LogicalResult matchAndRewrite(vector::MultiDimReductionOp op,
                                PatternRewriter &rewriter) const override {
    auto srcTy = op.getSourceVectorType();
    auto dstTy = dyn_cast<VectorType>(op.getDest().getType());
    if (op.isMasked() || srcTy.isScalable() || srcTy.getRank() != 2 ||
        srcTy.getShape()[1] != 2 || !dstTy ||
        dstTy.getShape() != ArrayRef<int64_t>({2}) ||
        op.getReductionDims() != ArrayRef<int64_t>({0}) ||
        op.getKind() != vector::CombiningKind::ADD)
      return failure();

    Type elemTy = srcTy.getElementType();
    if (!elemTy.isIntOrFloat())
      return failure();
    unsigned bitWidth = elemTy.getIntOrFloatBitWidth();
    if (bitWidth == 0 || bitWidth > 128 || 128 % bitWidth != 0)
      return failure();

    Location loc = op.getLoc();
    int64_t rows = srcTy.getShape()[0];
    int64_t numElems = srcTy.getNumElements();
    int64_t minLanes = 128 / bitWidth;
    auto flatTy = VectorType::get({numElems}, elemTy);
    auto bufferTy = MemRefType::get({numElems}, elemTy);
    auto pairTy = VectorType::get({2 * minLanes}, elemTy, {true});
    auto pairMaskTy = pairTy.cloneWith(std::nullopt, rewriter.getI1Type());

    auto pointerTy = LLVM::LLVMPointerType::get(rewriter.getContext());
    Value stack = LLVM::StackSaveOp::create(rewriter, loc, pointerTy);
    Value input = memref::AllocaOp::create(rewriter, loc, bufferTy);
    Value zero = arith::ConstantIndexOp::create(rewriter, loc, 0);
    Value two = arith::ConstantIndexOp::create(rewriter, loc, 2);
    Value upper = arith::ConstantIndexOp::create(rewriter, loc, rows);
    Value lanes = arith::ConstantIndexOp::create(rewriter, loc, minLanes);
    Value vscale = vector::VectorScaleOp::create(rewriter, loc);
    Value step = arith::MulIOp::create(rewriter, loc, lanes, vscale);
    Value flat =
        vector::ShapeCastOp::create(rewriter, loc, flatTy, op.getSource());
    vector::StoreOp::create(rewriter, loc, flat, input, ValueRange{zero});
    Value passthru = arith::ConstantOp::create(
        rewriter, loc,
        SplatElementsAttr::get(pairTy, rewriter.getZeroAttr(elemTy)));
    Value acc0 = vector::ExtractOp::create(rewriter, loc, op.getAcc(),
                                           ArrayRef<int64_t>{0});
    Value acc1 = vector::ExtractOp::create(rewriter, loc, op.getAcc(),
                                           ArrayRef<int64_t>{1});

    auto loop = scf::ForOp::create(
        rewriter, loc, zero, upper, step, ValueRange{acc0, acc1},
        [&](OpBuilder &builder, Location bodyLoc, Value index,
            ValueRange iterArgs) {
          Value remaining =
              arith::SubIOp::create(builder, bodyLoc, upper, index);
          Value pairCount =
              arith::MulIOp::create(builder, bodyLoc, remaining, two);
          Value mask = vector::CreateMaskOp::create(
              builder, bodyLoc, pairMaskTy, ValueRange{pairCount});
          Value pairIndex = arith::MulIOp::create(builder, bodyLoc, index, two);
          Value loaded = vector::MaskedLoadOp::create(
              builder, bodyLoc, pairTy, input, ValueRange{pairIndex}, mask,
              passthru);
          auto split = vector::DeinterleaveOp::create(builder, bodyLoc, loaded);
          Value next0 = vector::ReductionOp::create(
              builder, bodyLoc, vector::CombiningKind::ADD, split.getRes1(),
              iterArgs[0]);
          Value next1 = vector::ReductionOp::create(
              builder, bodyLoc, vector::CombiningKind::ADD, split.getRes2(),
              iterArgs[1]);
          scf::YieldOp::create(builder, bodyLoc, ValueRange{next0, next1});
        });

    Value result = vector::InsertOp::create(rewriter, loc, loop.getResult(0),
                                            op.getAcc(), ArrayRef<int64_t>{0});
    result = vector::InsertOp::create(rewriter, loc, loop.getResult(1), result,
                                      ArrayRef<int64_t>{1});
    LLVM::StackRestoreOp::create(rewriter, loc, stack);
    rewriter.replaceOp(op, result);
    return success();
  }
};

struct LowerSVE : public mlir::triton::cpu::impl::LowerSVEBase<LowerSVE> {
  using LowerSVEBase::LowerSVEBase;

  void runOnOperation() override {
    RewritePatternSet patterns(&getContext());
    patterns.add<LowerOuterReduction>(&getContext());
    if (failed(applyPatternsGreedily(getOperation(), std::move(patterns))))
      signalPassFailure();
  }
};

} // namespace

namespace mlir::triton::cpu {

std::unique_ptr<OperationPass<triton::FuncOp>> createLowerSVEPass() {
  return std::make_unique<LowerSVE>();
}

} // namespace mlir::triton::cpu
