# BitMatch Features Documentation

## Core Features

### 1. Copy & Verify
**Primary Function**: Copy files from a source folder to multiple backup destinations with integrity verification.

#### Workflow
1. **Source Selection**: Choose folder containing media files
2. **Destination Setup**: Select multiple backup drives/folders
3. **Camera Detection**: Automatic identification of camera type and metadata
4. **Folder Labeling**: Automatic naming based on camera and user preferences
5. **Verification**: Choose from multiple verification modes
6. **Transfer**: Simultaneous copy to all destinations with real-time progress
7. **Reporting**: Generate professional PDF and CSV reports

#### Key Benefits
- **Multiple Destinations**: Copy to multiple backups simultaneously
- **Integrity Verification**: Ensure perfect file copies with checksums
- **Professional Naming**: Industry-standard folder naming conventions
- **Real-time Progress**: Detailed progress with speed, ETA, and file counts
- **Camera Aware**: Automatic detection and labeling of camera media

### Operational Controls
- **Pause/Resume**: Safely pause and resume long operations
- **State Persistence**: Minimal snapshotting to protect progress across app sessions
- **Error Reporting**: Consolidated error summaries with exportable reports

### Performance & Caching
- **Persistent Checksum Cache**: Dramatically faster re‑verification (1h TTL; auto‑invalidates on file change)
- **Off‑Main Enumeration**: Folder analysis runs off the main thread to keep UI smooth
- **Parallel Batching**: Conservative concurrency to avoid I/O saturation

### 2. Compare Folders
**Primary Function**: Compare two folders to identify differences, missing files, and integrity issues.

#### Workflow
1. **Folder Selection**: Choose left (source of truth) and right (comparison) folders
2. **Comparison Options**: Configure comparison parameters
   - File sizes
   - Modification dates  
   - Checksum verification
3. **Analysis**: Deep comparison with detailed reporting
4. **Results**: Visual presentation of differences and issues

#### Key Benefits
- **Verification**: Confirm backup integrity
- **Difference Detection**: Identify missing or corrupted files
- **Detailed Analysis**: File-by-file comparison with metadata
- **Professional Reports**: Comprehensive comparison documentation

### 3. Master Report
**Primary Function**: Generate comprehensive reports from completed transfer operations across multiple volumes.

#### Workflow
1. **Volume Scanning**: Scan available drives for completed transfers
2. **Transfer Discovery**: Automatically find BitMatch transfer records
3. **Selection**: Choose transfers to include in master report
4. **Configuration**: Set production details and preferences
5. **Generation**: Create unified PDF and JSON reports
6. **Distribution**: Native sharing via iOS/macOS share sheets

#### Key Benefits
- **Production Documentation**: Complete transfer history for projects
- **Multi-Volume Analysis**: Scan multiple drives simultaneously
- **Professional Output**: Industry-standard report formatting
- **Metadata Rich**: Comprehensive technical and production metadata

## Verification Modes

### Quick Mode
- **Method**: File size comparison only
- **Speed**: Fastest
- **Use Case**: Basic verification for trusted environments
- **Time**: ~30 seconds per 1000 files

### Standard Mode (Default)
- **Method**: SHA-256 checksum verification
- **Speed**: Fast
- **Use Case**: Standard professional verification
- **Time**: ~2 minutes per 1000 files
- **Output**: SHA-256 checksums for all files

### Thorough Mode
- **Method**: Multiple checksum algorithms (SHA-256, MD5)
- **Speed**: Medium
- **Use Case**: High-security environments
- **Time**: ~4 minutes per 1000 files  
- **Output**: Dual checksums, MHL file generation
- **Compliance**: Netflix MHL standard

Note: MD5 support exists for interoperability with some legacy pipelines. For integrity verification, SHA‑256 is the recommended default.

### Paranoid Mode
- **Method**: Byte-by-byte comparison + multiple checksums
- **Speed**: Slowest but most comprehensive
- **Use Case**: Mission-critical data verification
- **Time**: ~6 minutes per 1000 files
- **Output**: Complete verification chain, detailed MHL records
- **Compliance**: Full Netflix MHL standard compliance

## Camera Detection System

### Supported Camera Types

#### Professional Cinema Cameras
- **ARRI**: Alexa Mini, Alexa 35, Amira
  - Detection: ARRIRAW folder structure, .ari files
  - Naming: ARRI_[Date]_[Roll]

- **RED**: Dragon, Komodo, V-Raptor  
  - Detection: .R3D files, RED folder structure
  - Naming: RED_[Camera]_[Date]

- **Sony**: FX6, FX3, FX9, A7S III
  - Detection: XAVC folder structure, .mxf files
  - Naming: SONY_[Model]_[Date]

- **Canon**: C70, C300 III, R5C
  - Detection: Canon folder structure, .mp4/.mxf files
  - Naming: CANON_[Model]_[Date]

#### Professional Video Cameras  
- **Blackmagic Design**: Pocket 4K/6K, URSA series
  - Detection: .braw files, Blackmagic folder structure
  - Naming: BMPCC_[Resolution]_[Date]

- **Panasonic**: GH5, EVA1, AU-EVA1
  - Detection: .mov/.mp4 files, Panasonic metadata
  - Naming: PANA_[Model]_[Date]

#### Consumer/Prosumer Cameras
- **Canon DSLR**: R5, R6, 5D Mark IV
  - Detection: DCIM structure, Canon .cr3/.mov files
  - Naming: CANON_[Model]_[Date]

- **Sony Mirrorless**: A7R V, A7 IV, FX30
  - Detection: DCIM structure, Sony .arw/.mp4 files  
  - Naming: SONY_[Model]_[Date]

- **GoPro**: Hero 11/12, Max
  - Detection: GoPro folder structure, .mp4 files
  - Naming: GOPRO_[Model]_[Date]

- **DJI**: Air 2S, Mini 3 Pro, Inspire series
  - Detection: DJI folder structure, drone metadata
  - Naming: DJI_[Model]_[Date]

#### Specialty Cameras
- **Insta360**: X3, RS series
  - Detection: .insv files, 360° metadata
  - Naming: I360_[Model]_[Date]

- **Fujifilm**: X-H2S, X-T5
  - Detection: Fujifilm .raf/.mov files
  - Naming: FUJI_[Model]_[Date]

### Detection Algorithms
1. **File Structure Analysis**: Examine folder hierarchy and naming patterns
2. **Metadata Extraction**: Read EXIF, XMP, and proprietary metadata
3. **File Signature Detection**: Identify camera-specific file formats
4. **Confidence Scoring**: Assign reliability scores to detections
5. **Fallback Patterns**: Generic DCIM detection for unknown cameras

## Folder Labeling System

### Naming Patterns
- **Prefix Mode**: `[Label]_[Original_Name]`
  - Example: `ACam_DCIM_001` 
- **Suffix Mode**: `[Original_Name]_[Label]`
  - Example: `DCIM_001_ACam`

### Separator Options
- **Underscore**: `ACam_DCIM_001` (Default, professional standard)
- **Dash**: `ACam-DCIM-001` (Alternative professional format)
- **Dot**: `ACam.DCIM.001` (Technical documentation style)
- **Space**: `ACam DCIM 001` (Human readable)

### Auto-Numbering
- **Conflict Detection**: Automatic detection of existing folders
- **Incremental Naming**: `ACam_001`, `ACam_002`, etc.
- **Smart Grouping**: Group files by camera type when enabled

### Quick Presets
- **A-Cam**, **B-Cam**, **C-Cam**: Standard multi-camera setups
- **Main**: Primary camera angle
- **Audio**: Dedicated audio recordings
- **Drone**: Aerial footage
- **D-Cam**: Additional camera angles

## Progress Tracking & Statistics

### Real-Time Metrics
- **Overall Progress**: Percentage completion across all destinations
- **Current File**: Name of file being processed
- **Files Processed**: Count of completed vs. total files
- **Transfer Speed**: Current and average MB/s
- **Time Remaining**: ETA based on current performance
- **Elapsed Time**: Time since operation start

### Enhanced Statistics
- **Peak Speed**: Maximum transfer rate achieved
- **Bytes Processed**: Data transferred vs. total
- **Stage Progress**: Current operation stage (copying, verifying, etc.)
- **Per-Destination Progress**: Individual progress for each backup
- **Error Count**: Number of issues encountered

### Performance Optimization
- **Adaptive Buffering**: Dynamic buffer sizes based on drive performance
- **Parallel Operations**: Simultaneous copies to multiple destinations
- **Smart Scheduling**: Optimal file ordering for sequential drives
- **Memory Management**: Efficient handling of large file sets

## Report Generation

### PDF Reports
- **Professional Formatting**: Industry-standard layout and typography
- **Comprehensive Metadata**: Complete technical details
- **Visual Elements**: Charts, graphs, and status indicators
- **Production Information**: Client, project, and technician details
- **Thumbnail Support**: Optional image previews

### CSV Reports  
- **Structured Data**: Machine-readable format for analysis
- **File-by-File Details**: Complete file listing with metadata
- **Checksum Records**: All verification data included
- **Import Ready**: Compatible with Excel, databases, and analysis tools

### JSON Reports
- **Technical Format**: Complete technical data export
- **API Compatible**: Ready for system integration
- **Nested Metadata**: Full hierarchical data structure
- **Version Controlled**: Format versioning for compatibility

### Report Content
- **Transfer Summary**: High-level operation overview
- **File Inventory**: Complete file listing with sizes and dates
- **Verification Results**: Checksum verification status
- **Error Log**: Any issues encountered during transfer
- **Performance Metrics**: Speed, timing, and efficiency data
- **Production Metadata**: Camera, project, and workflow information

## Platform-Specific Features

### macOS Exclusive
- **Menu Bar Integration**: Quick access to common functions
- **Window Management**: Adaptive window sizing based on content
- **Finder Integration**: Direct integration with macOS file system
- **Spotlight Integration**: Searchable report metadata

### iPad Exclusive  
- **Touch Optimization**: Gesture-based interactions
- **Collapsible Sections**: Space-efficient interface design
- **Native Share Sheet**: iOS-standard sharing capabilities
- **Files App Integration**: Direct access to iOS file system

### Cross-Platform Features
- **Consistent Data**: Identical verification and reporting across platforms
- **Shared Settings**: User preferences sync between devices
- **Universal Reports**: Reports generated on either platform are identical
- **Compatible Operations**: Transfer operations can be completed on either platform

## Security & Reliability

### Data Security
- **Security-Scoped Resources**: Proper iOS file system access management
- **Permission Handling**: Graceful handling of file system permissions
- **Safe File Operations**: Atomic operations prevent data corruption
- **Error Recovery**: Robust error handling and recovery mechanisms

### Reliability Features
- **Resume Capability**: Resume interrupted transfers
- **Progress Persistence**: Operation state survives app crashes
- **Checksum Verification**: Guarantee data integrity
- **Atomic Operations**: All-or-nothing file operations

### Industry Compliance
- **Netflix MHL**: Full Media Hash List standard compliance
- **Professional Standards**: Workflow compatibility with industry tools
- **Metadata Preservation**: Complete preservation of camera metadata
- **Audit Trail**: Complete documentation of all operations
