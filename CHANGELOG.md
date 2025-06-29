# LLM Toolkit SDK Changelog

## Version 0.0.2 - *June 29, 2025*

### 🚀 New Features
- **Enhanced Model Browser** with tabbed interface (Search, Recommended, Downloaded)
- **File Browser Integration** - Load models directly from device storage
- **Device-Specific Recommendations** - Memory-aware model suggestions based on device capabilities
- **Advanced Debug Console** - Real-time logging with color-coded categories and filtering
- **Improved Model Cards** - Better file organization, download status, and compatibility indicators
- **Native Library Validation** - Automatic detection of llama.cpp compatibility and health checks
- **Progressive Model Loading** - Fallback configurations for memory-constrained devices
- **Enhanced Error Handling** - Detailed error messages with troubleshooting tips and recovery suggestions

### 🔧 Improvements
- **Quantization Safety Checks** - Automatic detection and warnings for unstable quantizations (Q2_K, IQ1_S, IQ1_M)
- **Memory Management** - Dynamic context size adjustment based on available device memory
- **Download Progress** - Real-time progress indicators with speed metrics and ETA
- **Model Detection** - Improved engine detection for GGUF and TFLite files with better accuracy
- **UI/UX Enhancements** - Material Design 3 with gradient themes, better accessibility, and responsive design
- **Performance Monitoring** - Token generation speed tracking, memory usage reporting, and performance analytics
- **Search Optimization** - Better model discovery with multiple search strategies and relevance ranking

### 🐛 Bug Fixes
- Fixed SIGSEGV crashes with problematic quantizations on Android ARM64 devices
- Resolved memory leaks during model loading/unloading cycles
- Fixed download interruption handling and resume functionality
- Corrected model file validation for corrupted GGUF files
- Fixed context size calculation for low-memory devices
- Resolved engine detection issues for certain model formats
- Fixed UI state management during concurrent operations

### 📚 Documentation
- Added comprehensive model compatibility guide with device-specific recommendations
- Enhanced troubleshooting documentation for Android devices with common solutions
- Updated API documentation with new configuration options and examples
- Added performance optimization guidelines for mobile deployment

### 🛠️ Technical Improvements
- **Isolate-based Model Loading** - Better crash protection and memory isolation
- **Enhanced Logging System** - Categorized debug logs with filtering and export capabilities
- **Improved Error Recovery** - Graceful fallback mechanisms for failed operations
- **Better Resource Management** - Optimized memory usage and cleanup procedures

## Version 0.0.1 - *June 27, 2025*

### 🎉 Initial Release
- **Dual Engine Support** - Llama (GGUF) and Gemma (TFLite) inference engines
- **HuggingFace Integration** - Direct model search and download from HuggingFace Hub
- **Model Management** - Automatic model detection and configuration
- **Chat Interface** - Real-time streaming text generation with conversation history
- **Cross-Platform** - Support for Android and iOS devices

### 🔧 Core Features
- **Model Search** - Search and filter models by format, size, and compatibility
- **Automatic Downloads** - Background model downloading with progress tracking
- **Engine Detection** - Automatic selection of appropriate inference engine based on model format
- **Memory Optimization** - Dynamic configuration based on device capabilities
- **Error Handling** - Comprehensive exception handling and user feedback

### 📱 Supported Formats
- **GGUF** - Quantized models for efficient inference (Q4_K_M, Q4_0, Q5_K_M, Q8_0)
- **TFLite** - TensorFlow Lite models optimized for mobile devices
- **Model Types** - Support for Gemma, Llama, Phi, DeepSeek, and custom models

### 🛠️ Technical Stack
- **Flutter Framework** - Cross-platform mobile development
- **llama_cpp_dart** - Native GGUF model inference with ARM64 optimization
- **flutter_gemma** - TFLite model inference with GPU acceleration
- **Dio HTTP Client** - Efficient model downloading and API communication
- **Path Provider** - Cross-platform file system access and management

### 🎯 Initial Capabilities
- **Text Generation** - Streaming text generation with customizable parameters
- **Model Discovery** - Browse and search thousands of compatible models
- **Local Storage** - Efficient model caching and management
- **Debug Tools** - Basic logging and error reporting
- **Configuration Management** - Flexible inference configuration options
