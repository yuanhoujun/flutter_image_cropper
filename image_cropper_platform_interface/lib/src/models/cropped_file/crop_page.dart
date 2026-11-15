import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper_platform_interface/src/models/cropped_file/imagecropper_ohos.dart';
import 'package:image_cropper_platform_interface/src/models/cropped_file/crop.dart';
import 'dart:io';

class CropWidget extends StatefulWidget {
  final String imagePath;

  const CropWidget({
    Key? key,
    required this.imagePath,
  }) : super(key: key);

  @override
  State<CropWidget> createState() => _CropWidgetState();
}

class _CropWidgetState extends State<CropWidget> {
  File? _sampleFile;
  final GlobalKey<CropState> _cropKey = GlobalKey<CropState>();
  bool _isProcessing = false;
  final ImagecropperOhos _imageCropper = ImagecropperOhos();
  double? _currentAspectRatio;
  double _currentScale = 1.0;
  int _selectedTabIndex = 0; // 0: 裁剪, 1: 旋转, 2: 缩放
  double? _selectedAspectRatio; // 跟踪当前选中的比例
  late RotateController _rotateController;
  late ScaleController _scaleController; // 添加缩放控制器
  double _currentRotation = 0.0; // 当前旋转角度
  
  // UCrop标准颜色常量
  static const Color _uCropOrange = Color(0xFFFF6E40);
  static const Color _uCropDarkOrange = Color(0xFFE64A19);
  static const Color _uCropBackground = Color(0xFF212121);
  static const Color _uCropBottomBar = Color(0xFF424242);
  
  @override
  void initState() {
    super.initState();
    _rotateController = RotateController();
    _scaleController = ScaleController(); // 初始化缩放控制器
    _sampleImage();
  }
  
  @override
  void dispose() {
    _rotateController.dispose();
    _scaleController.dispose(); // 释放缩放控制器资源
    super.dispose();
  }

  void _sampleImage() async {
    try {
      final sampleFile = await _imageCropper.sampleImage(
        path: widget.imagePath,
        maximumSize: 1024,
      );
      if (!mounted) return;
      setState(() {
        _sampleFile = sampleFile;
      });
    } catch (e) {
      print('Sample image error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _uCropBackground,
      appBar: _buildUCropAppBar(),
      body: Column(
        children: [
          Expanded(
            child: _buildCroppingImage(),
          ),
          _buildUCropBottomControls(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildUCropAppBar() {
    return AppBar(
      backgroundColor: _uCropOrange,
      elevation: 0,
      systemOverlayStyle: const SystemUiOverlayStyle(
        statusBarColor: _uCropDarkOrange,
        statusBarIconBrightness: Brightness.light,
      ),
      leading: IconButton(
        icon: const Icon(
          Icons.close,
          color: Colors.white,
          size: 24,
        ),
        onPressed: () {
          Navigator.of(context).pop(null);
        },
      ),
      title: const Text(
        'Crop Image',
        style: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      ),
      centerTitle: false,
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          child: IconButton(
            onPressed: _isProcessing ? null : _cropImage,
            icon: Icon(
              Icons.check,
              color: _isProcessing ? Colors.white60 : Colors.white,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCroppingImage() {
    if (_sampleFile == null) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(_uCropOrange),
        ),
      );
    }

    return Container(
      color: _uCropBackground,
      child: Center(
        child: Container(
          child: Crop(
            key: _cropKey,
            image: FileImage(_sampleFile!),
            aspectRatio: _currentAspectRatio,
            rotateController: _rotateController,
            scaleController: _scaleController, // 传递缩放控制器
            initialScale: _currentScale,
            onRotationChanged: (double angle) {
              // 更新当前旋转角度
              setState(() {
                _currentRotation = angle % 360; // 保持角度在0-360范围内
              });
            },
          ),
        ),
      ),
    );
  }
  
  // 修改旋转方法
  void _rotateCrop(int degrees) {
    setState(() {
      _currentRotation += degrees;
      // 保持角度在 0-360 范围内
      _currentRotation = _currentRotation % 360;
    });
    
    // 使用旋转控制器旋转图片
    _rotateController.rotate?.call(_currentRotation);
  }
  
  void _resetCrop() {
    final cropState = _cropKey.currentState;
    if (cropState != null) {
      setState(() {
        _currentAspectRatio = null;
        _selectedAspectRatio = null;
        _currentScale = 1.0;
        _currentRotation = 0.0; // 重置旋转角度
      });
      _rotateController.rotate?.call(0.0); // 重置旋转
    }
  }

  Widget _buildUCropBottomControls() {
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 上层操作按钮区（白色背景，固定高度）
          Container(
            color: Colors.white,
            height: 64,
            child: Center(
              child: _buildCurrentTabContent(),
            ),
          ),
          // 下层功能分类区（黑色背景）
          Container(
            color: Colors.black,
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildUCropTabButton(
                  icon: Icons.crop,
                  label: '裁剪',
                  index: 0,
                  onPressed: () => _selectTab(0),
                ),
                _buildUCropTabButton(
                  icon: Icons.rotate_right,
                  label: '旋转',
                  index: 1,
                  onPressed: () => _selectTab(1),
                ),
                _buildUCropTabButton(
                  icon: Icons.zoom_in,
                  label: '缩放',
                  index: 2,
                  onPressed: () => _selectTab(2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectTab(int index) {
    setState(() {
      _selectedTabIndex = index;
    });
  }

  Widget _buildCurrentTabContent() {
    switch (_selectedTabIndex) {
      case 0: // 裁剪
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildTextOnlyButton('原始比例', () => _setAspectRatio(null), aspectRatio: null),
            _buildTextOnlyButton('1:1', () => _setAspectRatio(1.0), aspectRatio: 1.0),
            _buildTextOnlyButton('4:3', () => _setAspectRatio(4.0/3.0), aspectRatio: 4.0/3.0),
            _buildTextOnlyButton('2:3\n(customized)', () => _setAspectRatio(2.0/3.0), aspectRatio: 2.0/3.0),
          ],
        );
      case 1: // 旋转
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildWhiteBackgroundButton(Icons.rotate_left, '左转', () => _rotateCrop(-90)),
            _buildWhiteBackgroundButton(Icons.refresh, '重置', () => _resetCrop()),
            _buildWhiteBackgroundButton(Icons.rotate_right, '右转', () => _rotateCrop(90)),
          ],
        );
      case 2: // 缩放
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildWhiteBackgroundButton(Icons.zoom_out, '缩小', () => _zoomOut()),
            _buildWhiteBackgroundButton(Icons.refresh, '重置', () => _resetScale()),
            _buildWhiteBackgroundButton(Icons.zoom_in, '放大', () => _zoomIn()),
          ],
        );
      default:
        return Container();
    }
  }

  // 修改只显示文字的按钮样式，添加橘红色指示点
  Widget _buildTextOnlyButton(String label, VoidCallback onPressed, {double? aspectRatio}) {
    final isSelected = _selectedAspectRatio == aspectRatio;
    
    // 检查是否包含换行符
    final hasLineBreak = label.contains('\n');
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // 文本按钮
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFFFF6D00) : Colors.black87,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    height: hasLineBreak ? 1.2 : null, // 设置行高
                  ),
                ),
              ),
              // 橘红色指示点覆盖在下方
              if (isSelected)
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF6D00),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWhiteBackgroundButton(IconData icon, String label, VoidCallback onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: const Color(0xFFFF6D00),
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUCropTabButton({
    required IconData icon,
    required String label,
    required int index,
    required VoidCallback? onPressed,
  }) {
    final isSelected = _selectedTabIndex == index;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFFFF6D00) : Colors.white70,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFFFF6D00) : Colors.white70,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 设置宽高比方法
  void _setAspectRatio(double? ratio) {
    setState(() {
      _selectedAspectRatio = ratio;
      _currentAspectRatio = ratio;
    });
  }

  // 缩放方法（暂时保留原有逻辑，不使用缩放控制器）
  void _zoomIn() {
    final newScale = (_currentScale * 1.2).clamp(1.0, 3.0);
    setState(() {
      _currentScale = newScale;
    });
    // 使用 ScaleController 动态控制缩放
    _scaleController.setScale?.call(newScale);
  }

  void _zoomOut() {
    final newScale = (_currentScale / 1.2).clamp(1.0, 3.0);
    setState(() {
      _currentScale = newScale;
    });
    // 使用 ScaleController 动态控制缩放
    _scaleController.setScale?.call(newScale);
  }

  void _resetScale() {
    setState(() {
      _currentScale = 1.0;
    });
    // 使用 ScaleController 重置缩放
    _scaleController.setScale?.call(1.0);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1000),
        backgroundColor: _uCropOrange,
      ),
    );
  }

  void _cropImage() async {
    print('=== _cropImage 开始执行 ===');
    print('_isProcessing: $_isProcessing');
    print('_sampleFile: $_sampleFile');
    
    if (_isProcessing || _sampleFile == null) {
      print('提前返回：_isProcessing=$_isProcessing, _sampleFile=$_sampleFile');
      return;
    }
    
    final cropState = _cropKey.currentState;
    print('cropState: $cropState');
    print('cropState?.area: ${cropState?.area}');
    
    if (cropState?.area == null) {
      print('area 为 null，显示错误提示');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select crop area'),
          backgroundColor: Colors.red[600],
        ),
      );
      return;
    }

    print('开始设置 _isProcessing = true');
    setState(() {
      _isProcessing = true;
    });

    try {
      print('开始调用 cropImage，参数：');
      print('  file: ${_sampleFile!.path}');
      print('  area: ${cropState!.area!}');
      print('  angle: $_currentRotation');
      
      final croppedFile = await _imageCropper.cropImage(
        file: _sampleFile!,
        area: cropState!.area!,
        angle: _currentRotation,
      );
      
      print('cropImage 调用成功，结果：${croppedFile.path}');
      if (!mounted) return;
      Navigator.of(context).pop(croppedFile.path);
    } catch (e) {
      if (!mounted) return;
      print('cropImage 调用失败，错误：$e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Crop failed: $e'),
          backgroundColor: Colors.red[600],
        ),
      );
    } finally {
      print('设置 _isProcessing = false');
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
    print('=== _cropImage 执行结束 ===');
  }
}
