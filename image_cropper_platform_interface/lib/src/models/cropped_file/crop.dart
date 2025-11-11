import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'dart:ui' as ui;

const _kCropGridColumnCount = 3;
const _kCropGridRowCount = 3;
const _kCropGridColor = Color.fromRGBO(0xd0, 0xd0, 0xd0, 0.9);
const _kCropOverlayActiveOpacity = 0.3;
const _kCropOverlayInactiveOpacity = 0.7;
const _kCropHandleColor = Color.fromRGBO(0xd0, 0xd0, 0xd0, 1.0);
const _kCropHandleSize = 10.0;
const _kCropHandleHitSize = 48.0;
const _kCropMinFraction = 0.1;

enum _CropAction { none, moving, cropping, scaling }

enum _CropHandleSide { none, topLeft, topRight, bottomLeft, bottomRight }

class RotateController {
  Function(double angle)? rotate;

  void dispose() {
    rotate = null;
  }
}

// 添加缩放控制器
class ScaleController {
  Function(double scale)? setScale;

  void dispose() {
    setScale = null;
  }
}

class Crop extends StatefulWidget {
  final ImageProvider image;
  final double? aspectRatio;
  final double maximumScale;
  final bool alwaysShowGrid;
  final ImageErrorListener? onImageError;
  final RotateController? rotateController;
  final ScaleController? scaleController; // 添加缩放控制器
  final double initialScale;
  final Function(double angle)? onRotationChanged; // 添加旋转角度变化回调

  const Crop({
    Key? key,
    required this.image,
    this.aspectRatio,
    this.maximumScale = 2.0,
    this.alwaysShowGrid = true,
    this.onImageError,
    this.rotateController,
    this.scaleController, // 添加缩放控制器参数
    this.initialScale = 1.0,
    this.onRotationChanged, // 添加旋转角度变化回调参数
  }) : super(key: key);

  Crop.file(
    File file, {
    Key? key,
    double scale = 1.0,
    this.aspectRatio,
    this.maximumScale = 2.0,
    this.alwaysShowGrid = true,
    this.onImageError,
    this.rotateController,
    this.scaleController, // 添加缩放控制器参数
    this.initialScale = 1.0,
    this.onRotationChanged, // 添加旋转角度变化回调参数
  })  : image = FileImage(file, scale: scale),
        super(key: key);

  Crop.asset(
    String assetName, {
    Key? key,
    AssetBundle? bundle,
    String? package,
    this.aspectRatio,
    this.maximumScale = 2.0,
    this.alwaysShowGrid = true,
    this.onImageError,
    this.rotateController,
    this.scaleController, // 添加缩放控制器参数
    this.initialScale = 1.0,
    this.onRotationChanged, // 添加旋转角度变化回调参数
  })  : image = AssetImage(assetName, bundle: bundle, package: package),
        super(key: key);

  @override
  State<StatefulWidget> createState() => CropState();

  static CropState? of(BuildContext context) =>
      context.findAncestorStateOfType<CropState>();
}

class CropState extends State<Crop> with TickerProviderStateMixin {
  final _surfaceKey = GlobalKey();

  late final AnimationController _activeController;
  late final AnimationController _settleController;

  double _scale = 1.0;
  double _ratio = 1.0;
  double angle = 0;
  double cx = 0;
  double cy = 0;
  Rect _view = Rect.zero;
  Rect _area = Rect.zero;
  Offset _lastFocalPoint = Offset.zero;
  _CropAction _action = _CropAction.none;
  _CropHandleSide _handle = _CropHandleSide.none;

  late double _startAngle;
  late double _startScale;
  late Rect _startView;


  ImageStream? _imageStream;
  ui.Image? _image;
  ImageStreamListener? _imageListener;

  double get scale => _area.shortestSide / _scale;

  Rect? get area => _view.isEmpty
      ? null
      : Rect.fromLTWH(
          max(_area.left * _view.width - _view.left, 0),
          max(_area.top * _view.height - _view.top, 0),
          _area.width * _view.width,
          _area.height * _view.height,
        );

  bool get _isEnabled => _view.isEmpty == false && _image != null;

  // Saving the length for the widest area for different aspectRatio's
  final Map<double, double> _maxAreaWidthMap = {};

  // Counting pointers(number of user fingers on screen)
  int pointers = 0;

  @override
  @override
  void didUpdateWidget(Crop oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 处理initialScale的更新
    if (widget.initialScale != oldWidget.initialScale) {
      setState(() {
        _scale = widget.initialScale;
      });
    }
    
    // 处理aspectRatio的更新
    if (widget.aspectRatio != oldWidget.aspectRatio) {
      // 重新计算裁剪区域
      final image = _image;
      if (image != null) {
        setState(() {
          _area = _calculateDefaultArea(
            imageWidth: image.width,
            imageHeight: image.height,
            viewWidth: _view.width,
            viewHeight: _view.height,
          );
        });
      }
    }
    
    // 重新设置控制器
    _setupControllers();
  }

  @override
  void initState() {
    super.initState();
    
    _scale = widget.initialScale; // 使用初始缩放值
    
    _activeController = AnimationController(
      vsync: this,
      value: widget.alwaysShowGrid ? 1.0 : 0.0,
    )..addListener(() => setState(() {}));
    _settleController = AnimationController(vsync: this)
      ..addListener(_settleAnimationChanged);
    
    // 设置控制器回调
    _setupControllers();
  }
  
  
  // 添加新方法来设置旋转控制器
  void _setupControllers() {
    // 设置旋转控制器
    final rotateController = widget.rotateController;
    if (rotateController != null) {
      rotateController.rotate = (double rotationAngle) {
        setState(() {
          angle = rotationAngle;
          
          // 通知父组件旋转角度变化
          if (widget.onRotationChanged != null) {
            widget.onRotationChanged!(angle);
          }
        });
      };
    }
    
    // 设置缩放控制器
    final scaleController = widget.scaleController;
    if (scaleController != null) {
      scaleController.setScale = (double newScale) {
        final minimumScale = _minimumScale ?? 1.0;
        final targetScale = newScale.clamp(minimumScale, _maximumScale);
        final targetView = _getViewInBoundaries(targetScale);
        
        // 使用动画平滑过渡到新的缩放值
        _scaleTween = Tween<double>(
          begin: _scale,
          end: targetScale,
        );
        
        _viewTween = RectTween(
          begin: _view,
          end: targetView,
        );
        
        _settleController.value = 0.0;
        _settleController.animateTo(
          1.0,
          curve: Curves.fastOutSlowIn,
          duration: const Duration(milliseconds: 350),
        );
      };
    }
  }
  
  @override
  void dispose() {
    final listener = _imageListener;
    if (listener != null) {
      _imageStream?.removeListener(listener);
    }
    _activeController.dispose();
    _settleController.dispose();

    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _getImage();
  }

 

  void _getImage({bool force = false}) {
    final oldImageStream = _imageStream;
    final newImageStream =
        widget.image.resolve(createLocalImageConfiguration(context));
    _imageStream = newImageStream;
    if (newImageStream.key != oldImageStream?.key || force) {
      final oldImageListener = _imageListener;
      if (oldImageListener != null) {
        oldImageStream?.removeListener(oldImageListener);
      }
      final newImageListener =
          ImageStreamListener(_updateImage, onError: widget.onImageError);
      _imageListener = newImageListener;
      newImageStream.addListener(newImageListener);
    }
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints.expand(),
        child: Listener(
          onPointerDown: (event) => pointers++,
          onPointerUp: (event) => pointers = 0,
          child: GestureDetector(
            key: _surfaceKey,
            behavior: HitTestBehavior.opaque,
            onScaleStart: _isEnabled ? _handleScaleStart : null,
            onScaleUpdate: _isEnabled ? _handleScaleUpdate : null,
            onScaleEnd: _isEnabled ? _handleScaleEnd : null,
            child: CustomPaint(
              painter: _CropPainter(
                  image: _image,
                  ratio: _ratio,
                  view: _view,
                  area: _area,
                  scale: _scale,
                  angle: angle,
                  active: _activeController.value,
                  callback: (x, y) {
                    cx = x;
                    cy = y;
                  }),
            ),
          ),
        ),
      );

  void _activate() {
    _activeController.animateTo(
      1.0,
      curve: Curves.fastOutSlowIn,
      duration: const Duration(milliseconds: 250),
    );
  }

  void _deactivate() {
    if (widget.alwaysShowGrid == false) {
      _activeController.animateTo(
        0.0,
        curve: Curves.fastOutSlowIn,
        duration: const Duration(milliseconds: 250),
      );
    }
  }

  Size? get _boundaries {
    final context = _surfaceKey.currentContext;
    if (context == null) {
      return null;
    }

    final size = context.size;
    if (size == null) {
      return null;
    }

    return size - const Offset(_kCropHandleSize, _kCropHandleSize) as Size;
  }

  Offset? _getLocalPoint(Offset point) {
    final context = _surfaceKey.currentContext;
    if (context == null) {
      return null;
    }

    final box = context.findRenderObject() as RenderBox;

    return box.globalToLocal(point);
  }

  // 修改变量声明，提供默认值
  Tween<Rect?>? _viewTween;
  Tween<double>? _scaleTween;
  
  // 修改 _settleAnimationChanged 方法
  void _settleAnimationChanged() {
    setState(() {
      // 只有在 Tween 被正确初始化时才应用动画值
      if (_scaleTween != null) {
        _scale = _scaleTween!.transform(_settleController.value);
      }
      if (_viewTween != null) {
        final nextView = _viewTween!.transform(_settleController.value);
        if (nextView != null) {
          _view = nextView;
        }
      }
    });
  }

  Rect _calculateDefaultArea({
    required int? imageWidth,
    required int? imageHeight,
    required double viewWidth,
    required double viewHeight,
    double? defaultSize,
  }) {
    if (imageWidth == null || imageHeight == null) {
      return Rect.zero;
    }

    double height;
    double width;
    if ((widget.aspectRatio ?? 1.0) < 1) {
      height = defaultSize ?? 1.0;
      width =
          ((widget.aspectRatio ?? 1.0) * imageHeight * viewHeight * height) /
              imageWidth /
              viewWidth;
      if (width > 1.0) {
        width = 1.0;
        height = (imageWidth * viewWidth * width) /
            (imageHeight * viewHeight * (widget.aspectRatio ?? 1.0));
      }
    } else {
      width = defaultSize ?? 1.0;
      height = (imageWidth * viewWidth * width) /
          (imageHeight * viewHeight * (widget.aspectRatio ?? 1.0));
      if (height > 1.0) {
        height = 1.0;
        width =
            ((widget.aspectRatio ?? 1.0) * imageHeight * viewHeight * height) /
                imageWidth /
                viewWidth;
      }
    }
    final aspectRatio = _maxAreaWidthMap[widget.aspectRatio];
    if (aspectRatio != null) {
      _maxAreaWidthMap[aspectRatio] = width;
    }

    return Rect.fromLTWH((1.0 - width) / 2, (1.0 - height) / 2, width, height);
  }

  void _updateImage(ImageInfo imageInfo, bool synchronousCall) {
    final boundaries = _boundaries;
    if (boundaries == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      final image = imageInfo.image;

      setState(() {
        _image = image;
        _scale = imageInfo.scale;
        _ratio = max(
          boundaries.width / image.width,
          boundaries.height / image.height,
        );

        final viewWidth = boundaries.width / (image.width * _scale * _ratio);
        final viewHeight = boundaries.height / (image.height * _scale * _ratio);
        _area = _calculateDefaultArea(
          viewWidth: viewWidth,
          viewHeight: viewHeight,
          imageWidth: image.width,
          imageHeight: image.height,
          defaultSize: 0.9,
        );
        _view = Rect.fromLTWH(
          (viewWidth - 1.0) / 2,
          (viewHeight - 1.0) / 2,
          viewWidth,
          viewHeight,
        );
      });
    });

    WidgetsBinding.instance.ensureVisualUpdate();
  }

  _CropHandleSide _hitCropHandle(Offset? localPoint) {
    final boundaries = _boundaries;
    if (localPoint == null || boundaries == null) {
      return _CropHandleSide.none;
    }

    final viewRect = Rect.fromLTWH(
      boundaries.width * _area.left,
      boundaries.height * _area.top,
      boundaries.width * _area.width,
      boundaries.height * _area.height,
    ).deflate(_kCropHandleSize / 2);

    // 进一步增大触摸检测区域，使用更大的触摸范围
    const double touchSize = _kCropHandleHitSize * 2.0; // 增大到2倍

    if (Rect.fromLTWH(
      viewRect.left - touchSize / 2,
      viewRect.top - touchSize / 2,
      touchSize,
      touchSize,
    ).contains(localPoint)) {
      return _CropHandleSide.topLeft;
    }

    if (Rect.fromLTWH(
      viewRect.right - touchSize / 2,
      viewRect.top - touchSize / 2,
      touchSize,
      touchSize,
    ).contains(localPoint)) {
      return _CropHandleSide.topRight;
    }

    if (Rect.fromLTWH(
      viewRect.left - touchSize / 2,
      viewRect.bottom - touchSize / 2,
      touchSize,
      touchSize,
    ).contains(localPoint)) {
      return _CropHandleSide.bottomLeft;
    }

    if (Rect.fromLTWH(
      viewRect.right - touchSize / 2,
      viewRect.bottom - touchSize / 2,
      touchSize,
      touchSize,
    ).contains(localPoint)) {
      return _CropHandleSide.bottomRight;
    }

    return _CropHandleSide.none;
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _activate();
    _settleController.stop(canceled: false);
    _lastFocalPoint = details.focalPoint;
    _handle = _hitCropHandle(_getLocalPoint(details.focalPoint));
    _startScale = _scale;
    _startView = _view;
    _startAngle = angle;
    
    // 根据是否点击了裁剪手柄设置不同的操作模式
    if (_handle != _CropHandleSide.none) {
      // 如果点击了裁剪手柄，设置为裁剪模式
      _action = _CropAction.cropping;
    } else {
      // 否则根据触摸点数量设置为移动或缩放模式
      _action = pointers == 2 ? _CropAction.scaling : _CropAction.moving;
    }
  }

void _updateViewWithBoundaries(Rect newView) {
  final constrainedView = _getViewInBoundaries(_scale);
  setState(() {
    _view = constrainedView;
  });
}

  double get _maximumScale {
    // 简单返回用户设置的最大缩放值，或者设置一个合理的默认值
    return widget.maximumScale;
  }

  double? get _minimumScale {
    final boundaries = _boundaries;
    final image = _image;
    if (boundaries == null || image == null) {
      return 1.0;
    }
    
    // 计算裁剪框的尺寸
    final cropWidth = boundaries.width * _area.width;
    final cropHeight = boundaries.height * _area.height;
    
    // 计算图片在当前缩放下的尺寸
    final imageWidth = image.width * _ratio;
    final imageHeight = image.height * _ratio;
    
    // 计算最小缩放值，确保图片能够完全覆盖裁剪框
    final minScaleX = cropWidth / imageWidth;
    final minScaleY = cropHeight / imageHeight;
    final minRequiredScale = max(minScaleX, minScaleY);
    
    // 确保最小缩放值不小于1.0
    return max(1.0, minRequiredScale);
  }

  bool _checkIfOutOfBounds(Rect currentView, double scale) {
    final image = _image;
    final boundaries = _boundaries;
    if (image == null || boundaries == null) {
      return false;
    }
    
    // 计算图片和裁剪框的实际尺寸
    final imageWidth = image.width * scale * _ratio;
    final imageHeight = image.height * scale * _ratio;
    final cropWidth = boundaries.width * _area.width;
    final cropHeight = boundaries.height * _area.height;
    
    // 计算裁剪框在图片坐标系中的位置
    final cropLeft = boundaries.width * _area.left;
    final cropTop = boundaries.height * _area.top;
    
    // 计算图片当前位置的边界
    final imageLeft = currentView.left * imageWidth;
    final imageTop = currentView.top * imageHeight;
    final imageRight = imageLeft + imageWidth;
    final imageBottom = imageTop + imageHeight;
    
    // 检测是否超出边界
    bool outOfBounds = false;
    
    if (imageWidth > cropWidth) {
      // 图片宽度大于裁剪框时，检查是否完全覆盖裁剪框
      if (imageLeft > cropLeft || imageRight < (cropLeft + cropWidth)) {
        outOfBounds = true;
      }
    } else {
      // 图片宽度小于裁剪框时，检查是否居中
      final expectedLeft = cropLeft - (cropWidth - imageWidth) / 2;
      if ((imageLeft - expectedLeft).abs() > 1.0) {
        outOfBounds = true;
      }
    }
    
    if (imageHeight > cropHeight) {
      // 图片高度大于裁剪框时，检查是否完全覆盖裁剪框
      if (imageTop > cropTop || imageBottom < (cropTop + cropHeight)) {
        outOfBounds = true;
      }
    } else {
      // 图片高度小于裁剪框时，检查是否居中
      final expectedTop = cropTop - (cropHeight - imageHeight) / 2;
      if ((imageTop - expectedTop).abs() > 1.0) {
        outOfBounds = true;
      }
    }
    
    return outOfBounds;
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _deactivate();
    final minimumScale = _minimumScale;
    if (minimumScale == null) {
      return;
    }

    final targetScale = _scale.clamp(minimumScale, _maximumScale);
    
    // 自动检测位置是否超出裁剪框边界
    final targetView = _getViewInBoundaries(targetScale.toDouble());
    final isOutOfBounds = _checkIfOutOfBounds(_view, targetScale.toDouble());
    
    // 始终初始化 Tween，即使不需要动画
    _scaleTween = Tween<double>(
      begin: _scale,
      end: targetScale.toDouble(),
    );
    
    _viewTween = RectTween(
      begin: _view,
      end: targetView,
    );
    
    // 检查是否需要调整缩放值或位置
    final needsScaleAdjustment = (targetScale - _scale).abs() > 0.001;
    final needsPositionAdjustment = (targetView.left - _view.left).abs() > 0.001 || 
                                   (targetView.top - _view.top).abs() > 0.001;
    
    // 如果超出边界或需要调整，执行动画；否则直接设置最终值
    if (isOutOfBounds || needsScaleAdjustment || needsPositionAdjustment) {
      _settleController.value = 0.0;
      _settleController.animateTo(
        1.0,
        curve: Curves.fastOutSlowIn,
        duration: const Duration(milliseconds: 350),
      );
    } else {
      // 即使不需要动画，也要确保设置正确的最终值
      setState(() {
        _scale = targetScale.toDouble();
        _view = targetView;
      });
    }
  }

  void _updateArea({
    required _CropHandleSide cropHandleSide,
    double? left,
    double? top,
    double? right,
    double? bottom,
  }) {
    final image = _image;
    if (image == null) {
      return;
    }

    var areaLeft = _area.left + (left ?? 0.0);
    var areaBottom = _area.bottom + (bottom ?? 0.0);
    var areaTop = _area.top + (top ?? 0.0);
    var areaRight = _area.right + (right ?? 0.0);
    double width = areaRight - areaLeft;
    double height = (image.width * _view.width * width) /
        (image.height * _view.height * (widget.aspectRatio ?? 1.0));
    final maxAreaWidth = _maxAreaWidthMap[widget.aspectRatio];
    if ((height >= 1.0 || width >= 1.0) && maxAreaWidth != null) {
      height = 1.0;

      if (cropHandleSide == _CropHandleSide.bottomLeft ||
          cropHandleSide == _CropHandleSide.topLeft) {
        areaLeft = areaRight - maxAreaWidth;
      } else {
        areaRight = areaLeft + maxAreaWidth;
      }
    }

    // ensure minimum rectangle
    if (areaRight - areaLeft < _kCropMinFraction) {
      if (left != null) {
        areaLeft = areaRight - _kCropMinFraction;
      } else {
        areaRight = areaLeft + _kCropMinFraction;
      }
    }

    if (areaBottom - areaTop < _kCropMinFraction) {
      if (top != null) {
        areaTop = areaBottom - _kCropMinFraction;
      } else {
        areaBottom = areaTop + _kCropMinFraction;
      }
    }

    // adjust to aspect ratio if needed
    final aspectRatio = widget.aspectRatio;
    if (aspectRatio != null && aspectRatio > 0.0) {
      if (top != null) {
        areaTop = areaBottom - height;
        if (areaTop < 0.0) {
          areaTop = 0.0;
          areaBottom = height;
        }
      } else {
        areaBottom = areaTop + height;
        if (areaBottom > 1.0) {
          areaTop = 1.0 - height;
          areaBottom = 1.0;
        }
      }
    }

    // ensure to remain within bounds of the view
    if (areaLeft < 0.0) {
      areaLeft = 0.0;
      areaRight = _area.width;
    } else if (areaRight > 1.0) {
      areaLeft = 1.0 - _area.width;
      areaRight = 1.0;
    }

    if (areaTop < 0.0) {
      areaTop = 0.0;
      areaBottom = _area.height;
    } else if (areaBottom > 1.0) {
      areaTop = 1.0 - _area.height;
      areaBottom = 1.0;
    }

    setState(() {
      _area = Rect.fromLTRB(areaLeft, areaTop, areaRight, areaBottom);
    });
  }

  Rect _getViewInBoundaries(double scale) {
    final image = _image;
    final boundaries = _boundaries;
    if (image == null || boundaries == null) {
      return _view;
    }
    
    // 重新计算视图尺寸
    final viewWidth = boundaries.width / (image.width * scale * _ratio);
    final viewHeight = boundaries.height / (image.height * scale * _ratio);
    
    // 计算图片和裁剪框的实际尺寸
    final imageWidth = image.width * scale * _ratio;
    final imageHeight = image.height * scale * _ratio;
    final cropWidth = boundaries.width * _area.width;
    final cropHeight = boundaries.height * _area.height;
    
    // 计算裁剪框在图片坐标系中的位置
    final cropLeft = boundaries.width * _area.left;
    final cropTop = boundaries.height * _area.top;
    
    // 计算边界约束
    double left, top;
    
    if (imageWidth <= cropWidth) {
      // 图片宽度小于等于裁剪框，图片应该居中
      final centerOffset = (cropWidth - imageWidth) / 2;
      left = (cropLeft - centerOffset) / imageWidth;
    } else {
      // 图片宽度大于裁剪框，确保图片完全覆盖裁剪框
      final maxLeft = cropLeft / imageWidth;
      final minLeft = (cropLeft + cropWidth - imageWidth) / imageWidth;
      left = _view.left.clamp(minLeft, maxLeft);
    }
    
    if (imageHeight <= cropHeight) {
      // 图片高度小于等于裁剪框，图片应该居中
      final centerOffset = (cropHeight - imageHeight) / 2;
      top = (cropTop - centerOffset) / imageHeight;
    } else {
      // 图片高度大于裁剪框，确保图片完全覆盖裁剪框
      final maxTop = cropTop / imageHeight;
      final minTop = (cropTop + cropHeight - imageHeight) / imageHeight;
      top = _view.top.clamp(minTop, maxTop);
    }
    
    return Rect.fromLTWH(left, top, viewWidth, viewHeight);
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_action == _CropAction.none) {
      if (_handle == _CropHandleSide.none) {
        _action = pointers == 2 ? _CropAction.scaling : _CropAction.moving;
      } else {
        _action = _CropAction.cropping;
      }
    }

    if (_action == _CropAction.cropping) {
      final image = _image;
      final boundaries = _boundaries;
      if (image == null || boundaries == null || _handle == _CropHandleSide.none) {
        return;
      }

      final delta = details.focalPoint - _lastFocalPoint;
      _lastFocalPoint = details.focalPoint;
      
      // 根据拖动的手柄和偏移量计算裁剪框的调整值
      final handle = _handle;
      final ratio = boundaries.width / boundaries.height;
      
      // 计算单位偏移量对应的裁剪区域变化
      final deltaX = delta.dx / boundaries.width;
      final deltaY = delta.dy / boundaries.height;
      
      // 根据不同的手柄计算相应的调整值
      switch (handle) {
        case _CropHandleSide.topLeft:
          _updateArea(
            cropHandleSide: handle,
            left: deltaX,
            top: deltaY,
          );
          break;
        case _CropHandleSide.topRight:
          _updateArea(
            cropHandleSide: handle,
            right: deltaX,
            top: deltaY,
          );
          break;
        case _CropHandleSide.bottomLeft:
          _updateArea(
            cropHandleSide: handle,
            left: deltaX,
            bottom: deltaY,
          );
          break;
        case _CropHandleSide.bottomRight:
          _updateArea(
            cropHandleSide: handle,
            right: deltaX,
            bottom: deltaY,
          );
          break;
        default:
          break;
      }

    } else if (_action == _CropAction.moving) {
      final image = _image;
      final boundaries = _boundaries;
      if (image == null || boundaries == null) {
        return;
      }

      final delta = details.focalPoint - _lastFocalPoint;
      _lastFocalPoint = details.focalPoint;

      final an = angle / 180 * pi;

      var dx1 = delta.dy * sin(an);
      var dx2 = delta.dx * cos(an);

      var dy1 = delta.dy * cos(an);
      var dy2 = -delta.dx * sin(an);

      // 计算新的视图位置，不应用边界约束
      final newView = _view.translate(
        (dx1 + dx2) / (image.width * _scale * _ratio),
        (dy1 + dy2) / (image.height * _scale * _ratio),
      );
      
      setState(() {
        _view = newView;
      });
    } else if (_action == _CropAction.scaling) {
      final image = _image;
      final boundaries = _boundaries;
      if (image == null || boundaries == null) {
        return;
      }

      final newScale = (_startScale * details.scale).clamp(
        _minimumScale ?? 1.0, 
        _maximumScale
      );
      
      setState(() {
        _scale = newScale.toDouble();
        angle = _startAngle + details.rotation / pi * 180;
        
        // 通知父组件旋转角度变化
        if (widget.onRotationChanged != null) {
          widget.onRotationChanged!(angle);
        }

        final dx = boundaries.width *
            (1.0 - details.scale) /
            (image.width * _startScale * _ratio);
        final dy = boundaries.height *
            (1.0 - details.scale) /
            (image.height * _startScale * _ratio);

        // 计算新的视图位置
        final newView = _startView.translate(dx, dy);
        
        // 实时应用边界约束
        _view = _getViewInBoundaries(newScale.toDouble());
      });
    }
  }
}

class _CropPainter extends CustomPainter {
  final ui.Image? image;
  final Rect view;
  final double ratio;
  final Rect area;
  final double scale;
  final double active;
  final double angle;
  final Function(double cx, double cy) callback;

  _CropPainter({
    required this.image,
    required this.view,
    required this.ratio,
    required this.area,
    required this.scale,
    required this.active,
    required this.angle,
    required this.callback,
  });

  @override
  bool shouldRepaint(_CropPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.view != view ||
        oldDelegate.ratio != ratio ||
        oldDelegate.area != area ||
        oldDelegate.active != active ||
        oldDelegate.scale != scale;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      _kCropHandleSize / 2,
      _kCropHandleSize / 2,
      size.width - _kCropHandleSize,
      size.height - _kCropHandleSize,
    );
    final boundaries = Rect.fromLTWH(
      rect.width * area.left,
      rect.height * area.top,
      rect.width * area.width,
      rect.height * area.height,
    );

    canvas.save();
    canvas.translate(rect.left, rect.top);

    final paint = Paint()..isAntiAlias = false;

    final image = this.image;
    if (image != null) {
      final src = Rect.fromLTWH(
        0.0,
        0.0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dst = Rect.fromLTWH(
        view.left * image.width * scale * ratio,
        view.top * image.height * scale * ratio,
        image.width * scale * ratio,
        image.height * scale * ratio,
      );

      //--任意中心
      var cx = (boundaries.right + boundaries.left) * 0.5; //旋转中心=画布中心
      var cy = (boundaries.bottom + boundaries.top) * 0.5; //旋转中心=画布中心

      var cyr = cy - dst.top;
      var cxr = cx - dst.left;

      callback(cxr, cyr);

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle * pi / 180);
      canvas.translate(-cx, -cy);
      canvas.drawImageRect(image, src, dst, paint);
      canvas.restore();
    }

    paint.color = Color.fromRGBO(
        0x0,
        0x0,
        0x0,
        _kCropOverlayActiveOpacity * active +
            _kCropOverlayInactiveOpacity * (1.0 - active));

    canvas.drawRect(Rect.fromLTRB(0.0, 0.0, rect.width, boundaries.top), paint);
    canvas.drawRect(
        Rect.fromLTRB(0.0, boundaries.bottom, rect.width, rect.height), paint);
    canvas.drawRect(
        Rect.fromLTRB(0.0, boundaries.top, boundaries.left, boundaries.bottom),
        paint);
    canvas.drawRect(
        Rect.fromLTRB(
            boundaries.right, boundaries.top, rect.width, boundaries.bottom),
        paint);

    if (boundaries.isEmpty == false) {
      _drawGrid(canvas, boundaries);
      _drawHandles(canvas, boundaries);
    }

    canvas.restore();
  }

  void _drawHandles(Canvas canvas, Rect boundaries) {
    final paint = Paint()
      ..isAntiAlias = true
      ..color = _kCropHandleColor;

    canvas.drawOval(
      Rect.fromLTWH(
        boundaries.left - _kCropHandleSize / 2,
        boundaries.top - _kCropHandleSize / 2,
        _kCropHandleSize,
        _kCropHandleSize,
      ),
      paint,
    );

    canvas.drawOval(
      Rect.fromLTWH(
        boundaries.right - _kCropHandleSize / 2,
        boundaries.top - _kCropHandleSize / 2,
        _kCropHandleSize,
        _kCropHandleSize,
      ),
      paint,
    );

    canvas.drawOval(
      Rect.fromLTWH(
        boundaries.right - _kCropHandleSize / 2,
        boundaries.bottom - _kCropHandleSize / 2,
        _kCropHandleSize,
        _kCropHandleSize,
      ),
      paint,
    );

    canvas.drawOval(
      Rect.fromLTWH(
        boundaries.left - _kCropHandleSize / 2,
        boundaries.bottom - _kCropHandleSize / 2,
        _kCropHandleSize,
        _kCropHandleSize,
      ),
      paint,
    );
  }

  void _drawGrid(Canvas canvas, Rect boundaries) {
    if (active == 0.0) return;

    final paint = Paint()
      ..isAntiAlias = false
      ..color = _kCropGridColor.withOpacity(_kCropGridColor.opacity * active)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path()
      ..moveTo(boundaries.left, boundaries.top)
      ..lineTo(boundaries.right, boundaries.top)
      ..lineTo(boundaries.right, boundaries.bottom)
      ..lineTo(boundaries.left, boundaries.bottom)
      ..lineTo(boundaries.left, boundaries.top);

    for (var column = 1; column < _kCropGridColumnCount; column++) {
      path
        ..moveTo(
            boundaries.left + column * boundaries.width / _kCropGridColumnCount,
            boundaries.top)
        ..lineTo(
            boundaries.left + column * boundaries.width / _kCropGridColumnCount,
            boundaries.bottom);
    }

    for (var row = 1; row < _kCropGridRowCount; row++) {
      path
        ..moveTo(boundaries.left,
            boundaries.top + row * boundaries.height / _kCropGridRowCount)
        ..lineTo(boundaries.right,
            boundaries.top + row * boundaries.height / _kCropGridRowCount);
    }

    canvas.drawPath(path, paint);
  }
}
