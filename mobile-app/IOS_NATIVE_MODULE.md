# Meta Wearables DAT SDK - iOS Native Module

## Guía para crear el Native Module de Meta Ray-Ban en iOS

### Prerrequisitos

1. macOS con Xcode 15+
2. Conocimiento básico de Swift/Objective-C
3. Meta Developer App creada
4. Meta Wearables DAT SDK descargado

---

## Paso 1: Descargar Meta Wearables DAT SDK

```bash
# Clonar el repo oficial de Meta
git clone https://github.com/facebook/meta-wearables-dat-ios.git

# El SDK incluye:
# - MWDATCore.xcframework (conexión y registro de dispositivos)
# - MWDATCamera.xcframework (streaming de video y captura de fotos)
```

---

## Paso 2: Abrir el proyecto iOS de Expo

```bash
cd mobile-app
npx expo prebuild --platform ios
open ios/VoiceSwap.xcworkspace
```

---

## Paso 3: Añadir los Frameworks al proyecto

1. En Xcode, selecciona el proyecto `VoiceSwap`
2. Ve a **General → Frameworks, Libraries, and Embedded Content**
3. Click en **+** y selecciona **Add Other → Add Files...**
4. Navega a los `.xcframework` del SDK de Meta:
   - `MWDATCore.xcframework`
   - `MWDATCamera.xcframework`
5. Marca **Embed & Sign**

---

## Paso 4: Crear el Native Module

### 4.1 Crear `MetaWearablesDAT.swift`

**Ubicación**: `ios/VoiceSwap/MetaWearablesDAT.swift`

```swift
import Foundation
import React
import MWDATCore
import MWDATCamera

@objc(MetaWearablesDAT)
class MetaWearablesDAT: RCTEventEmitter {

  // MARK: - Properties

  private var wearables: WearablesInterface?
  private var streamSession: StreamSession?
  private var hasListeners = false

  // MARK: - Module Setup

  override static func requiresMainQueueSetup() -> Bool {
    return true
  }

  override func supportedEvents() -> [String]! {
    return [
      "onConnectionStateChanged",
      "onPhotoCaptured",
      "onVideoFrame",
      "onButtonPress"
    ]
  }

  override func startObserving() {
    hasListeners = true
  }

  override func stopObserving() {
    hasListeners = false
  }

  // MARK: - Initialization

  @objc
  func initialize(_ resolve: @escaping RCTPromiseResolveBlock,
                  rejecter reject: @escaping RCTPromiseRejectBlock) {
    DispatchQueue.main.async {
      do {
        // Initialize Meta Wearables Interface
        self.wearables = try WearablesInterface()

        // Subscribe to device updates
        self.subscribeToDeviceUpdates()

        resolve(true)
      } catch {
        reject("INIT_ERROR", "Failed to initialize Meta SDK", error)
      }
    }
  }

  // MARK: - Device Management

  private func subscribeToDeviceUpdates() {
    guard let wearables = wearables else { return }

    // Monitor registration state
    wearables.registrationStateStream()
      .sink { [weak self] state in
        self?.handleRegistrationStateChange(state)
      }
      .store(in: &cancellables)

    // Monitor connected devices
    wearables.devicesStream()
      .sink { [weak self] devices in
        self?.handleDevicesUpdate(devices)
      }
      .store(in: &cancellables)
  }

  private func handleRegistrationStateChange(_ state: RegistrationState) {
    guard hasListeners else { return }

    var eventData: [String: Any] = [:]

    switch state {
    case .registered(let device):
      eventData["state"] = "connected"
      eventData["device"] = [
        "id": device.identifier,
        "name": device.name,
        "model": device.model,
        "batteryLevel": device.batteryLevel ?? -1,
        "firmwareVersion": device.firmwareVersion ?? "",
        "serialNumber": device.serialNumber ?? ""
      ]

    case .registering:
      eventData["state"] = "connecting"

    case .unregistered:
      eventData["state"] = "disconnected"

    case .failed(let error):
      eventData["state"] = "error"
      print("[MetaWearablesDAT] Registration failed: \\(error)")
    }

    sendEvent(withName: "onConnectionStateChanged", body: eventData)
  }

  private func handleDevicesUpdate(_ devices: [Device]) {
    // Handle device list updates if needed
    print("[MetaWearablesDAT] Devices updated: \\(devices.count)")
  }

  // MARK: - Camera Methods

  @objc
  func capturePhoto(_ resolve: @escaping RCTPromiseResolveBlock,
                    rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard let wearables = wearables else {
      reject("NOT_INITIALIZED", "Meta SDK not initialized", nil)
      return
    }

    // Check camera permission
    guard wearables.checkPermissionStatus(.camera) == .authorized else {
      reject("PERMISSION_DENIED", "Camera permission not granted", nil)
      return
    }

    // Create stream session for photo capture
    let config = StreamSessionConfig(
      videoCodec: .raw,
      resolution: .medium,
      frameRate: 24
    )

    do {
      let session = try StreamSession(config, wearables.deviceSelector)

      // Capture photo
      session.capturePhoto(format: .jpeg) { [weak self] result in
        switch result {
        case .success(let photoData):
          // Save photo and return URI
          if let uri = self?.savePhotoData(photoData) {
            resolve(uri)
          } else {
            reject("SAVE_FAILED", "Failed to save photo", nil)
          }

        case .failure(let error):
          reject("CAPTURE_FAILED", "Failed to capture photo", error)
        }
      }
    } catch {
      reject("SESSION_ERROR", "Failed to create stream session", error)
    }
  }

  @objc
  func startVideoStream(_ config: NSDictionary,
                        resolver resolve: @escaping RCTPromiseResolveBlock,
                        rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard let wearables = wearables else {
      reject("NOT_INITIALIZED", "Meta SDK not initialized", nil)
      return
    }

    // Parse config
    let videoCodec: VideoCodec = (config["videoCodec"] as? String == "h264") ? .h264 : .raw
    let resolution: StreamingResolution = .low // Parse from config
    let frameRate = config["frameRate"] as? Int ?? 24

    let streamConfig = StreamSessionConfig(
      videoCodec: videoCodec,
      resolution: resolution,
      frameRate: frameRate
    )

    do {
      let session = try StreamSession(streamConfig, wearables.deviceSelector)
      self.streamSession = session

      // Subscribe to video frames
      session.videoFramePublisher
        .sink { [weak self] frame in
          self?.handleVideoFrame(frame)
        }
        .store(in: &cancellables)

      // Start streaming
      Task {
        do {
          try await session.start()
          let sessionId = UUID().uuidString
          resolve(sessionId)
        } catch {
          reject("START_FAILED", "Failed to start video stream", error)
        }
      }
    } catch {
      reject("SESSION_ERROR", "Failed to create stream session", error)
    }
  }

  @objc
  func stopVideoStream(_ sessionId: String?,
                       resolver resolve: @escaping RCTPromiseResolveBlock,
                       rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard let session = streamSession else {
      resolve(true)
      return
    }

    Task {
      await session.stop()
      self.streamSession = nil
      resolve(true)
    }
  }

  @objc
  func checkCameraPermission(_ resolve: @escaping RCTPromiseResolveBlock,
                             rejecter reject: @escaping RCTPromiseRejectBlock) {
    guard let wearables = wearables else {
      resolve(false)
      return
    }

    let status = wearables.checkPermissionStatus(.camera)
    resolve(status == .authorized)
  }

  // MARK: - Helper Methods

  private func savePhotoData(_ data: Data) -> String? {
    // Save to temporary directory
    let tempDir = FileManager.default.temporaryDirectory
    let fileName = "meta_photo_\\(UUID().uuidString).jpg"
    let fileURL = tempDir.appendingPathComponent(fileName)

    do {
      try data.write(to: fileURL)
      return fileURL.path
    } catch {
      print("[MetaWearablesDAT] Failed to save photo: \\(error)")
      return nil
    }
  }

  private func handleVideoFrame(_ frame: VideoFrame) {
    guard hasListeners else { return }

    // Convert frame to image URI (save to temp file)
    // In production, you might stream this more efficiently

    sendEvent(withName: "onVideoFrame", body: [
      "timestamp": frame.timestamp,
      "imageUri": "", // Would save frame and return URI
      "width": frame.width,
      "height": frame.height
    ])
  }

  // MARK: - Combine Support

  private var cancellables = Set<AnyCancellable>()
}
```

### 4.2 Crear `MetaWearablesDAT.m` (Bridging)

**Ubicación**: `ios/VoiceSwap/MetaWearablesDAT.m`

```objc
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface RCT_EXTERN_MODULE(MetaWearablesDAT, RCTEventEmitter)

RCT_EXTERN_METHOD(initialize:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(capturePhoto:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(startVideoStream:(NSDictionary *)config
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(stopVideoStream:(NSString *)sessionId
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(checkCameraPermission:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

+ (BOOL)requiresMainQueueSetup
{
  return YES;
}

@end
```

### 4.3 Crear Bridging Header (si no existe)

**Ubicación**: `ios/VoiceSwap/VoiceSwap-Bridging-Header.h`

```objc
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
```

---

## Paso 5: Configurar Build Settings

1. En Xcode, selecciona el target `VoiceSwap`
2. Ve a **Build Settings**
3. Busca "Objective-C Bridging Header"
4. Set valor: `VoiceSwap/VoiceSwap-Bridging-Header.h`

---

## Paso 6: Rebuild el proyecto

```bash
cd mobile-app
npx expo run:ios
```

---

## Testing

Verifica que el módulo funciona:

```typescript
import { NativeModules } from 'react-native';

const { MetaWearablesDAT } = NativeModules;

// Initialize
await MetaWearablesDAT.initialize();

// Capture photo
const photoUri = await MetaWearablesDAT.capturePhoto();
console.log('Photo captured:', photoUri);
```

---

## Troubleshooting

### Error: "Module not found"
- Verifica que los archivos `.swift` y `.m` están en el target de Xcode
- Rebuild: `npx expo run:ios --clean`

### Error: "Framework not found MWDATCore"
- Verifica que los frameworks están en **Embed & Sign**
- Framework Search Paths debe incluir la ruta de los `.xcframework`

### Error: "Bridging header not found"
- Verifica la ruta en Build Settings
- Ruta debe ser relativa al proyecto: `VoiceSwap/VoiceSwap-Bridging-Header.h`

---

## Alternativa: Bluetooth Fallback

Si el Native Module toma mucho tiempo, puedes usar el modo Bluetooth estándar:

1. En `MetaGlassesService.ts`, `useOfficialSDK` será `false`
2. La app usará Bluetooth del sistema (sin features de cámara)
3. Audio y voice commands funcionarán normalmente

Para producción, implementa el Native Module para acceder a la cámara.

---

## Referencias

- [Meta Wearables DAT SDK](https://github.com/facebook/meta-wearables-dat-ios)
- [React Native Native Modules](https://reactnative.dev/docs/native-modules-ios)
- [Expo Config Plugins](https://docs.expo.dev/guides/config-plugins/)
