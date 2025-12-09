/**
 * Meta Glasses Service - Official Meta Wearables DAT SDK Integration
 *
 * Uses the official Meta Wearables Device Access Toolkit (DAT) for iOS.
 * SDK: https://github.com/facebook/meta-wearables-dat-ios
 *
 * SDK Modules:
 * - MWDATCore: Device registration, connection management
 * - MWDATCamera: Video streaming, photo capture
 *
 * Key APIs (from SDK samples):
 * - WearablesInterface: Main SDK interface
 *   - .devices / .devicesStream() - Device list
 *   - .registrationState / .registrationStateStream() - Connection status
 *   - .startRegistration() / .startUnregistration() - Connect/disconnect
 *   - .checkPermissionStatus(.camera) - Permission check
 *
 * - StreamSession: Video/photo handling
 *   - StreamSessionConfig(videoCodec, resolution, frameRate)
 *   - .start() / .stop() - Streaming control
 *   - .capturePhoto(format: .jpeg) - Photo capture
 *   - .videoFramePublisher / .photoDataPublisher - Event streams
 *
 * Audio strategy (hybrid approach):
 * - Connection/status: Official Meta DAT SDK (MWDATCore)
 * - Camera/video: Official Meta DAT SDK (MWDATCamera)
 * - Audio routing: Standard Bluetooth HFP/A2DP (SDK doesn't expose audio APIs)
 * - Speech recognition: System STT via connected Bluetooth mic
 *
 * Fallback: Standard Bluetooth if SDK not available (Android, older iOS)
 */

import { Platform, NativeModules, NativeEventEmitter } from 'react-native';

// Try to import native Meta DAT module (will be null if not linked)
// In production, this would be a native module bridging MWDATCore + MWDATCamera
const MetaWearablesDAT = NativeModules.MetaWearablesDAT;
const hasMetaSDK = !!MetaWearablesDAT && Platform.OS === 'ios';

// Connection states
export type ConnectionState = 'disconnected' | 'connecting' | 'connected' | 'error';

// Device info - enhanced with SDK data when available
export interface MetaDevice {
  id: string;
  name: string;
  model: 'Wayfarer' | 'Headliner' | 'Stories' | 'Unknown';
  batteryLevel: number;        // -1 if unknown, 0-100 if available
  isBluetoothAudio: boolean;
  hasCamera: boolean;          // True for glasses with camera
  firmwareVersion?: string;    // Available via SDK
  serialNumber?: string;       // Available via SDK
}

// Camera capabilities (via SDK - MWDATCamera)
export interface CameraCapabilities {
  canCapturePhoto: boolean;
  canStreamVideo: boolean;
  maxVideoResolution?: string;
  supportedFormats?: ('jpeg' | 'heic')[];
}

// Stream configuration (matches SDK's StreamSessionConfig)
export interface StreamConfig {
  videoCodec: 'raw' | 'h264';
  resolution: 'low' | 'medium' | 'high';
  frameRate: number;
}

// Video frame from stream
export interface VideoFrame {
  timestamp: number;
  imageUri: string; // Local file URI
  width: number;
  height: number;
}

// Photo data from capture
export interface PhotoData {
  timestamp: number;
  imageUri: string;
  format: 'jpeg' | 'heic';
  width: number;
  height: number;
}

// Event callbacks
export type ConnectionCallback = (state: ConnectionState, device?: MetaDevice) => void;
export type ButtonCallback = (button: 'capture' | 'assistant') => void;
export type PhotoCallback = (photo: PhotoData) => void;
export type VideoFrameCallback = (frame: VideoFrame) => void;

// Known Meta glasses name patterns (for Bluetooth fallback)
const META_DEVICE_PATTERNS = [
  /ray-ban.*meta/i,
  /wayfarer/i,
  /headliner/i,
  /meta.*stories/i,
];

// SDK event types
interface SDKConnectionEvent {
  state: string;
  device?: {
    id: string;
    name: string;
    model: string;
    batteryLevel?: number;
    firmwareVersion?: string;
    serialNumber?: string;
  };
}

// Model type
type GlassesModel = 'Wayfarer' | 'Headliner' | 'Stories' | 'Unknown';

/**
 * MetaGlassesService - Hybrid SDK + Bluetooth Integration
 *
 * Strategy:
 * 1. If Meta DAT SDK is available (iOS): Use official SDK for connection/camera
 * 2. Fallback to standard Bluetooth for Android or if SDK unavailable
 * 3. Audio always routes via system Bluetooth (HFP/A2DP) - SDK doesn't expose audio
 *
 * This provides:
 * - Best-in-class integration on iOS via official SDK
 * - Cross-platform support via Bluetooth fallback
 * - Camera access for QR scanning (SDK feature)
 */
class MetaGlassesService {
  private connectionState: ConnectionState = 'disconnected';
  private connectedDevice: MetaDevice | null = null;
  private connectionCallbacks: ConnectionCallback[] = [];
  private buttonCallbacks: ButtonCallback[] = [];
  private photoCallbacks: PhotoCallback[] = [];
  private videoFrameCallbacks: VideoFrameCallback[] = [];
  private pollingInterval: ReturnType<typeof setInterval> | null = null;
  private sdkEventEmitter: NativeEventEmitter | null = null;

  // SDK availability
  private useOfficialSDK: boolean = hasMetaSDK;

  // Mock mode for development
  private mockMode: boolean = true;

  constructor() {
    const mode = this.useOfficialSDK ? 'Meta DAT SDK' : 'Standard Bluetooth';
    console.log(`[MetaGlassesService] Initialized (${mode} mode)`);

    // Setup SDK event listeners if available
    if (this.useOfficialSDK && MetaWearablesDAT) {
      this.setupSDKEventListeners();
    }
  }

  /**
   * Setup event listeners for Meta DAT SDK
   */
  private setupSDKEventListeners(): void {
    if (!MetaWearablesDAT) return;

    this.sdkEventEmitter = new NativeEventEmitter(MetaWearablesDAT);

    // Connection state changes
    this.sdkEventEmitter.addListener('onConnectionStateChanged', (event: SDKConnectionEvent) => {
      console.log('[MetaGlassesService] SDK connection event:', event);
      this.handleSDKConnectionChange(event);
    });

    // Photo captured (from SDK's photoDataPublisher)
    this.sdkEventEmitter.addListener('onPhotoCaptured', (event: {
      uri: string;
      format: 'jpeg' | 'heic';
      width: number;
      height: number;
      timestamp: number;
    }) => {
      console.log('[MetaGlassesService] Photo captured:', event.uri);
      const photoData: PhotoData = {
        timestamp: event.timestamp || Date.now(),
        imageUri: event.uri,
        format: event.format || 'jpeg',
        width: event.width || 0,
        height: event.height || 0,
      };
      this.photoCallbacks.forEach(cb => cb(photoData));
    });

    // Video frames (from SDK's videoFramePublisher)
    this.sdkEventEmitter.addListener('onVideoFrame', (event: {
      uri: string;
      width: number;
      height: number;
      timestamp: number;
    }) => {
      const frame: VideoFrame = {
        timestamp: event.timestamp || Date.now(),
        imageUri: event.uri,
        width: event.width || 0,
        height: event.height || 0,
      };
      this.videoFrameCallbacks.forEach(cb => cb(frame));
    });

    // Button press (if SDK exposes it)
    this.sdkEventEmitter.addListener('onButtonPress', (event: { button: string }) => {
      const button = event.button as 'capture' | 'assistant';
      this.buttonCallbacks.forEach(cb => cb(button));
    });
  }

  /**
   * Handle connection state changes from SDK
   */
  private handleSDKConnectionChange(event: {
    state: string;
    device?: {
      id: string;
      name: string;
      model: string;
      batteryLevel?: number;
      firmwareVersion?: string;
      serialNumber?: string;
    };
  }): void {
    switch (event.state) {
      case 'connected':
        if (event.device) {
          this.connectedDevice = {
            id: event.device.id,
            name: event.device.name,
            model: this.detectModel(event.device.model || event.device.name) as GlassesModel,
            batteryLevel: event.device.batteryLevel ?? -1,
            isBluetoothAudio: true,
            hasCamera: true,
            firmwareVersion: event.device.firmwareVersion,
            serialNumber: event.device.serialNumber,
          };
        }
        this.setConnectionState('connected');
        break;
      case 'connecting':
        this.setConnectionState('connecting');
        break;
      case 'disconnected':
        this.connectedDevice = null;
        this.setConnectionState('disconnected');
        break;
      case 'error':
        this.setConnectionState('error');
        break;
    }
  }

  /**
   * Initialize - Start monitoring for glasses
   */
  async initialize(): Promise<void> {
    try {
      if (this.useOfficialSDK && MetaWearablesDAT) {
        // Initialize official SDK
        await MetaWearablesDAT.initialize();
        console.log('[MetaGlassesService] Meta DAT SDK initialized');
      } else {
        // Fallback: Start polling for Bluetooth audio device
        await this.checkBluetoothAudio();

        // Poll every 5 seconds for connection changes
        this.pollingInterval = setInterval(() => {
          this.checkBluetoothAudio();
        }, 5000);

        console.log('[MetaGlassesService] Bluetooth monitoring started');
      }
    } catch (error) {
      console.error('[MetaGlassesService] Initialization failed:', error);

      // Fallback to Bluetooth if SDK fails
      if (this.useOfficialSDK) {
        console.log('[MetaGlassesService] Falling back to Bluetooth mode');
        this.useOfficialSDK = false;
        await this.initialize();
      }
    }
  }

  /**
   * Check current Bluetooth audio connection (fallback mode)
   */
  private async checkBluetoothAudio(): Promise<void> {
    // In production with react-native-bluetooth-classic or expo-bluetooth:
    // const connectedDevices = await BluetoothManager.getConnectedDevices(['A2DP', 'HFP']);
    // const audioDevice = connectedDevices.find(d => this.isMetaDevice(d.name));

    // For now, just log - mock mode handles the demo
    if (!this.mockMode) {
      console.log('[MetaGlassesService] Checking Bluetooth audio...');
    }
  }

  /**
   * Check if a device name matches Meta glasses patterns
   */
  private isMetaDevice(deviceName: string): boolean {
    return META_DEVICE_PATTERNS.some(pattern => pattern.test(deviceName));
  }

  /**
   * Detect device model from name
   */
  private detectModel(deviceName: string): GlassesModel {
    const lower = deviceName.toLowerCase();
    if (lower.includes('wayfarer')) return 'Wayfarer';
    if (lower.includes('headliner')) return 'Headliner';
    if (lower.includes('stories')) return 'Stories';
    return 'Unknown';
  }

  /**
   * Start scanning - On standard BT, just check current connections
   * User must pair via system Bluetooth settings
   */
  async startScanning(): Promise<void> {
    if (this.connectionState === 'connected') {
      console.warn('[MetaGlassesService] Already connected');
      return;
    }

    this.setConnectionState('connecting');

    // In production: Check for already-connected BT audio devices
    // The user pairs Meta glasses through iOS/Android Bluetooth settings

    // Mock: Simulate finding a device
    if (this.mockMode) {
      setTimeout(() => {
        this.mockConnect();
      }, 1500);
    }
  }

  /**
   * "Connect" - Really just registers that we detected the glasses
   * Actual connection happens via system Bluetooth
   */
  async connectToDevice(deviceId: string): Promise<void> {
    this.setConnectionState('connecting');
    console.log(`[MetaGlassesService] Registering device: ${deviceId}`);
    // Audio routing is automatic when BT is connected at system level
  }

  /**
   * Disconnect - Clear our tracking (doesn't affect system BT)
   */
  async disconnect(): Promise<void> {
    this.connectedDevice = null;
    this.setConnectionState('disconnected');
    console.log('[MetaGlassesService] Device unregistered');
  }

  /**
   * Audio handling - No-op because system handles BT audio routing
   * When glasses are connected via system BT, audio automatically routes there
   */
  async startAudioStream(): Promise<void> {
    if (this.connectionState !== 'connected') {
      throw new Error('Not connected to glasses');
    }
    // Audio routing is automatic - speech recognition uses connected BT mic
    console.log('[MetaGlassesService] Audio routes through system Bluetooth');
  }

  async stopAudioStream(): Promise<void> {
    // No-op - system handles audio
  }

  /**
   * TTS goes to glasses automatically when BT audio is connected
   * expo-speech respects the system audio route
   */
  async speakThroughGlasses(text: string): Promise<void> {
    // expo-speech automatically uses the connected Bluetooth audio device
    // No special handling needed
    console.log(`[MetaGlassesService] TTS will route to ${this.connectedDevice?.name || 'phone speaker'}`);
  }

  /**
   * Button detection - Simplified approach
   *
   * Option 1: Long-press volume button (detected via volume change events)
   * Option 2: Use system assistant activation (if supported)
   * Option 3: Wake word detection ("Hey VoiceSwap")
   *
   * The Meta glasses' touch controls are handled by the glasses firmware
   * and can trigger the phone's assistant. We can hook into that.
   */
  onButtonPress(callback: ButtonCallback): () => void {
    this.buttonCallbacks.push(callback);

    // In production: Listen for volume button events or assistant activation
    // react-native-volume-manager can detect volume button presses

    return () => {
      this.buttonCallbacks = this.buttonCallbacks.filter((cb) => cb !== callback);
    };
  }

  /**
   * Connection change listener
   */
  onConnectionChange(callback: ConnectionCallback): () => void {
    this.connectionCallbacks.push(callback);
    callback(this.connectionState, this.connectedDevice || undefined);

    return () => {
      this.connectionCallbacks = this.connectionCallbacks.filter((cb) => cb !== callback);
    };
  }

  /**
   * Photo capture listener (SDK feature)
   */
  onPhotoCaptured(callback: PhotoCallback): () => void {
    this.photoCallbacks.push(callback);
    return () => {
      this.photoCallbacks = this.photoCallbacks.filter((cb) => cb !== callback);
    };
  }

  // ============================================
  // SDK Camera Features (Meta DAT SDK only)
  // ============================================

  /**
   * Capture a photo from glasses camera
   * Only available when using official Meta DAT SDK
   *
   * Use cases:
   * - Scan QR codes for wallet addresses
   * - Capture receipts/invoices
   * - Visual confirmation of transactions
   */
  async capturePhoto(): Promise<string | null> {
    if (!this.useOfficialSDK || !MetaWearablesDAT) {
      console.warn('[MetaGlassesService] Photo capture requires Meta DAT SDK');
      return null;
    }

    if (this.connectionState !== 'connected') {
      throw new Error('Not connected to glasses');
    }

    if (!this.connectedDevice?.hasCamera) {
      throw new Error('Connected device does not have a camera');
    }

    try {
      const photoUri = await MetaWearablesDAT.capturePhoto();
      console.log('[MetaGlassesService] Photo captured:', photoUri);
      return photoUri;
    } catch (error) {
      console.error('[MetaGlassesService] Photo capture failed:', error);
      throw error;
    }
  }

  /**
   * Start video streaming from glasses camera
   *
   * SDK equivalent:
   * ```swift
   * let config = StreamSessionConfig(
   *     videoCodec: VideoCodec.raw,
   *     resolution: StreamingResolution.low,
   *     frameRate: 24
   * )
   * streamSession = StreamSession(config, deviceSelector)
   * await streamSession.start()
   * ```
   *
   * @param config - Stream configuration
   * @param onFrame - Callback for each video frame
   * @returns Session ID for stopping the stream
   */
  async startVideoStream(
    config?: Partial<StreamConfig>,
    onFrame?: VideoFrameCallback
  ): Promise<string | null> {
    if (!this.useOfficialSDK || !MetaWearablesDAT) {
      console.warn('[MetaGlassesService] Video streaming requires Meta DAT SDK');
      return null;
    }

    if (this.connectionState !== 'connected') {
      throw new Error('Not connected to glasses');
    }

    // Check camera permission first (SDK: wearables.checkPermissionStatus(.camera))
    const hasPermission = await this.checkCameraPermission();
    if (!hasPermission) {
      throw new Error('Camera permission not granted');
    }

    try {
      // Configure stream (matches SDK's StreamSessionConfig)
      const streamConfig: StreamConfig = {
        videoCodec: config?.videoCodec || 'raw',
        resolution: config?.resolution || 'low',
        frameRate: config?.frameRate || 24,
      };

      // Register frame callback if provided
      if (onFrame) {
        this.videoFrameCallbacks.push(onFrame);
      }

      // Start stream via native module
      const sessionId = await MetaWearablesDAT.startVideoStream(streamConfig);
      console.log('[MetaGlassesService] Video stream started:', sessionId);
      return sessionId;
    } catch (error) {
      console.error('[MetaGlassesService] Video stream failed:', error);
      throw error;
    }
  }

  /**
   * Stop video streaming
   * SDK equivalent: streamSession.stop()
   */
  async stopVideoStream(sessionId?: string): Promise<void> {
    if (!this.useOfficialSDK || !MetaWearablesDAT) return;

    try {
      await MetaWearablesDAT.stopVideoStream(sessionId);
      this.videoFrameCallbacks = []; // Clear callbacks
      console.log('[MetaGlassesService] Video stream stopped');
    } catch (error) {
      console.error('[MetaGlassesService] Failed to stop video stream:', error);
    }
  }

  /**
   * Check camera permission status
   * SDK equivalent: wearables.checkPermissionStatus(.camera)
   */
  async checkCameraPermission(): Promise<boolean> {
    if (!this.useOfficialSDK || !MetaWearablesDAT) return false;

    try {
      return await MetaWearablesDAT.checkCameraPermission();
    } catch {
      return false;
    }
  }

  /**
   * Get camera capabilities
   */
  getCameraCapabilities(): CameraCapabilities {
    if (!this.useOfficialSDK || !this.connectedDevice?.hasCamera) {
      return {
        canCapturePhoto: false,
        canStreamVideo: false,
      };
    }

    return {
      canCapturePhoto: true,
      canStreamVideo: true,
      maxVideoResolution: '1080p', // Ray-Ban Meta specs
    };
  }

  /**
   * Check if SDK features are available
   */
  hasSDKFeatures(): boolean {
    return this.useOfficialSDK && !!MetaWearablesDAT;
  }

  // Getters
  getConnectionState(): ConnectionState {
    return this.connectionState;
  }

  getConnectedDevice(): MetaDevice | null {
    return this.connectedDevice;
  }

  isConnected(): boolean {
    return this.connectionState === 'connected';
  }

  // Private
  private setConnectionState(state: ConnectionState): void {
    this.connectionState = state;
    this.connectionCallbacks.forEach((cb) => cb(state, this.connectedDevice || undefined));
  }

  // Cleanup
  destroy(): void {
    if (this.pollingInterval) {
      clearInterval(this.pollingInterval);
    }
  }

  // Mock methods for development without hardware

  mockConnect(): void {
    this.connectedDevice = {
      id: 'bt-audio-001',
      name: 'Ray-Ban Meta Wayfarer',
      model: 'Wayfarer',
      batteryLevel: 85, // Simulated battery level
      isBluetoothAudio: true,
      hasCamera: true,
    };
    this.setConnectionState('connected');
    console.log('[MetaGlassesService] Mock: Simulated Bluetooth audio connection');
  }

  mockDisconnect(): void {
    this.connectedDevice = null;
    this.setConnectionState('disconnected');
    console.log('[MetaGlassesService] Mock: Simulated disconnection');
  }

  mockButtonPress(button: 'capture' | 'assistant'): void {
    this.buttonCallbacks.forEach((cb) => cb(button));
  }

  setMockMode(enabled: boolean): void {
    this.mockMode = enabled;
  }
}

// Export singleton
export const metaGlassesService = new MetaGlassesService();

export default MetaGlassesService;
