//
//  CameraService.swift
//  CameraService
//
//  Created by Kamil Wyszomierski on 23/10/2019.
//  Copyright © 2019 Kamil Wyszomierski. All rights reserved.
//

import AVKit
import Combine
import Repository

public class CameraService: NSObject, CameraServiceProtocol {

	// MARK: - Properties

	public let output = PassthroughSubject<CameraOutput, Never>()

	private(set) var status = Status.notConfigured
	
	private let captureDeviceFactory: CaptureDeviceAbstractFactory
	private let outputQueue = DispatchQueue(label: "camera.output")
	private let session: CaptureSession

	// MARK: - Initialization

	public init(session: CaptureSession, captureDeviceFactory: CaptureDeviceAbstractFactory) {
		self.session = session
		self.captureDeviceFactory = captureDeviceFactory
	}

	// MARK: - Session

	public func startSession() throws {
		session.beginConfiguration()
		try addInput()
		try addOutput()
		session.commitConfiguration()
		session.startRunning()
		status = .running
	}

	public func stopSession() {
		guard status == .running else { return }
		session.stopRunning()
		status = .stopped
	}

	private func addOutput() throws {
		let output = AVCaptureVideoDataOutput()
		let needsOutput = session.outputs.isEmpty
		guard needsOutput else { return }

		output.setSampleBufferDelegate(self, queue: outputQueue)
		guard session.canAddOutput(output) else {
			let error = CameraServiceError.cannotAddPhotoOutputToSession
			status = .error(error)
			throw error
		}

		session.sessionPreset = .inputPriority
		session.addOutput(output)
	}

	private func addInput() throws {
		guard let videoDevice = captureDeviceFactory.makeBuildInWideBackVideoDevice() else {
			let error = CameraServiceError.cannotFindVideoDevice
			status = .error(error)
			throw error
		}

		let input = try captureDeviceFactory.makeCaptureDeviceInput(device: videoDevice)
		let needsInput = session.inputs.isEmpty
		guard needsInput else { return }

		guard session.canAddInput(input) else {
			let error = CameraServiceError.cannotAddDeviceInputToSession
			status = .error(error)
			throw error
		}

		session.addInput(input)
	}
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {

	public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
		guard
			let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
			let exifOrientation = CGImagePropertyOrientation(rawValue: UInt32(UIDevice.current.orientation.rawValue))
		else { return }

		let cameraIntrinsicData = CMGetAttachment(
			sampleBuffer,
			key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix,
			attachmentModeOut: nil
		)
		let output = CameraOutput(pixelBuffer: pixelBuffer, orientation: exifOrientation, intrinsics: cameraIntrinsicData)
		self.output.send(output)
	}
}

// MARK: - Status

extension CameraService {

	enum Status {
		case error(Error)
		case notConfigured
		case running
		case stopped
	}
}

extension CameraService.Status: Equatable {

	static func == (lhs: CameraService.Status, rhs: CameraService.Status) -> Bool {
		switch (lhs, rhs) {
		case (.error, .error),
			 (.notConfigured, .notConfigured),
			 (.running, .running),
			 (.stopped, .stopped):
			return true

		default:
			return false
		}
	}
}
