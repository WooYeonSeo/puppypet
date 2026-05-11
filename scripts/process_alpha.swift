#!/usr/bin/env swift

import Foundation
import AVFoundation
import Vision
import CoreImage

// 사용법:
//   ./process_alpha.swift                          → puppy_move.mp4 → puppy_alpha.mov (기본)
//   ./process_alpha.swift INPUT OUTPUT             → 임의 경로 처리
let args = CommandLine.arguments
let defaultIn = "/Users/yeonseowoo/dev/project/puppy/puppy/puppy/puppy_move.mp4"
let defaultOut = "/Users/yeonseowoo/dev/project/puppy/puppy/puppy/puppy_alpha.mov"
let inputURL = URL(fileURLWithPath: args.count > 1 ? args[1] : defaultIn)
let outputURL = URL(fileURLWithPath: args.count > 2 ? args[2] : defaultOut)
print("In:  \(inputURL.path)")
print("Out: \(outputURL.path)")

func process() async throws {
    try? FileManager.default.removeItem(at: outputURL)

    let asset = AVURLAsset(url: inputURL)
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    guard let track = videoTracks.first else { fatalError("no video track") }

    let naturalSize = try await track.load(.naturalSize)
    let preferredTransform = try await track.load(.preferredTransform)
    let frameRate = try await track.load(.nominalFrameRate)
    print("Input: \(Int(naturalSize.width))x\(Int(naturalSize.height)) @ \(frameRate)fps")

    // Reader: BGRA로 frame 디코딩
    let reader = try AVAssetReader(asset: asset)
    let readerOut = AVAssetReaderTrackOutput(track: track, outputSettings: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ])
    reader.add(readerOut)

    // Writer: HEVC with alpha
    let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
    let writerSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
        AVVideoWidthKey: Int(naturalSize.width),
        AVVideoHeightKey: Int(naturalSize.height)
    ]
    let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerSettings)
    writerInput.transform = preferredTransform
    writerInput.expectsMediaDataInRealTime = false

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: writerInput,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(naturalSize.width),
            kCVPixelBufferHeightKey as String: Int(naturalSize.height)
        ]
    )
    writer.add(writerInput)

    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    reader.startReading()

    var frameCount = 0
    var fellBack = 0
    while let sample = readerOut.copyNextSampleBuffer() {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()

        var outputBuffer: CVPixelBuffer = pixelBuffer
        do {
            try handler.perform([request])
            if let observation = request.results?.first {
                outputBuffer = try observation.generateMaskedImage(
                    ofInstances: observation.allInstances,
                    from: handler,
                    croppedToInstancesExtent: false
                )
            } else {
                fellBack += 1
            }
        } catch {
            fellBack += 1
            print("Frame \(frameCount) Vision error: \(error)")
        }

        while !writerInput.isReadyForMoreMediaData {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        adaptor.append(outputBuffer, withPresentationTime: pts)

        frameCount += 1
        if frameCount % 24 == 0 { print("  \(frameCount) frames…") }
    }

    writerInput.markAsFinished()
    await writer.finishWriting()
    print("Done. \(frameCount) frames total, \(fellBack) fell back to original.")

    if let attrs = try? FileManager.default.attributesOfItem(atPath: outputURL.path),
       let size = attrs[.size] as? Int {
        print("Output: \(outputURL.lastPathComponent) \(size / 1024)KB")
    }
}

let sem = DispatchSemaphore(value: 0)
Task {
    do { try await process() } catch { print("Error: \(error)") }
    sem.signal()
}
sem.wait()
