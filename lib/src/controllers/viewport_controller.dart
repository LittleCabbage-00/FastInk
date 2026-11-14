import 'dart:async';

import 'package:flutter/material.dart';

import '../core/document_viewport_layout.dart';

/// 文稿视口状态：缩放矩阵、页面布局、相机导航和动画。
class ViewportController {
  /// 建立相机矩阵和回正动画，vsync 由宿主提供，控制器离开宿主前必须释放。
  ViewportController(TickerProvider vsync)
    : zoomController = TransformationController(),
      zoomReturnController = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 280),
      );

  // ── 缩放 ────────────────────────────────────────────────────────────────
  /// zoomController：连续文稿相机矩阵通知器，平移缩放主要更新 Transform 而不是页面树。
  final TransformationController zoomController;

  /// zoomReturnController：惯性或回正相机动画的控制器，用户再次操作时需停止。
  final AnimationController zoomReturnController;

  /// zoomReturnAnimation：正在执行的相机矩阵插值，为空表示没有回正目标。
  Animation<Matrix4>? zoomReturnAnimation;

  // ── 文稿布局 ─────────────────────────────────────────────────────────────
  /// documentViewportLayout：连续文稿当前几何布局，必须与实际文稿和视口尺寸匹配。
  DocumentViewportLayout? documentViewportLayout;

  /// documentLayoutId：布局当前所属文稿编号，防止换文稿时复用旧几何。
  String? documentLayoutId;

  /// pageGeometryRevision：页面几何版本，尺寸、方向或页序变化后需重建布局。
  int pageGeometryRevision = 0;

  /// documentLayoutRevision：当前布局已应用的页面几何版本。
  int documentLayoutRevision = -1;

  /// documentLayoutReferenceRatio：建立连续文稿统一宽度时采用的参考宽高比。
  double documentLayoutReferenceRatio = 0;

  // ── 相机导航 ─────────────────────────────────────────────────────────────
  /// pendingViewportPage：下一次有效布局需要定位的页索引。
  int? pendingViewportPage;

  /// pendingVisiblePage：相机中心变化后等待防抖确认的可见页索引。
  int? pendingVisiblePage;

  /// visiblePageTimer：可见页变更防抖任务，快速跨页只装载最终目标附近内容。
  Timer? visiblePageTimer;

  /// cameraNavigationTarget：由页码导航发起的相机目标页，完成或手势接管时清空。
  int? cameraNavigationTarget;

  /// cameraNavigationTimer：尚未执行的相机导航任务，用户触摸或换文稿时取消。
  Timer? cameraNavigationTimer;

  // ── 触控板 ───────────────────────────────────────────────────────────────
  /// trackpadScaleOrigin：触控板捏合的累计比例基准，避免把每次更新当作独立缩放。
  double trackpadScaleOrigin = 1;

  /// trackpadStartMatrix：触控板手势开始时的相机快照，结束后清空以表明不再交互。
  Matrix4? trackpadStartMatrix;

  // ── 计算属性 ─────────────────────────────────────────────────────────────

  /// 收紧缩放矩阵到 [maxZoom] 上限。
  Matrix4 constrainZoom(Matrix4 matrix, double maxZoom) {
    final double current = matrix.getMaxScaleOnAxis();
    if (current <= maxZoom) return matrix;
    final double factor = maxZoom / current;
    return Matrix4.diagonal3Values(factor, factor, 1) * matrix;
  }

  // ── 生命周期 ─────────────────────────────────────────────────────────────

  /// 取消可见页/相机导航任务并释放矩阵和动画控制器，避免旧回调接管新文稿。
  void dispose() {
    visiblePageTimer?.cancel();
    cameraNavigationTimer?.cancel();
    zoomReturnController.dispose();
    zoomController.dispose();
  }
}
