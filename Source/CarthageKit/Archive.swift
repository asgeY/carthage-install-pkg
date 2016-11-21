//
//  Archive.swift
//  Carthage
//
//  Created by Justin Spahr-Summers on 2014-12-26.
//  Copyright (c) 2014 Carthage. All rights reserved.
//

import Foundation
import Result
import ReactiveCocoa
import ReactiveTask

/// Zips the given input paths (recursively) into an archive that will be
/// located at the given URL.
public func zip(paths paths: [String], into archiveURL: NSURL, workingDirectory: String) -> SignalProducer<(), CarthageError> {
	precondition(!paths.isEmpty)
	precondition(archiveURL.fileURL)

	let task = Task("/usr/bin/env", workingDirectoryPath: workingDirectory, arguments: [ "zip", "-q", "-r", "--symlinks", archiveURL.path! ] + paths)
	
	return task.launch()
		.mapError(CarthageError.taskError)
		.then(.empty)
}

/// Unzips the archive at the given file URL, extracting into the given
/// directory URL (which must already exist).
public func unzip(archive fileURL: NSURL, to destinationDirectoryURL: NSURL) -> SignalProducer<(), CarthageError> {
	precondition(fileURL.fileURL)
	precondition(destinationDirectoryURL.fileURL)

	let task = Task("/usr/bin/env", arguments: [ "unzip", "-qq", "-d", destinationDirectoryURL.path!, fileURL.path! ])
	return task.launch()
		.mapError(CarthageError.taskError)
		.then(.empty)
}

/// Unzips the archive at the given file URL into a temporary directory, then
/// sends the file URL to that directory.
public func unzip(archive fileURL: NSURL) -> SignalProducer<NSURL, CarthageError> {
	return SignalProducer.attempt { () -> Result<String, CarthageError> in
			var temporaryDirectoryTemplate: [CChar] = (NSTemporaryDirectory() as NSString).stringByAppendingPathComponent("carthage-archive.XXXXXX").nulTerminatedUTF8.map { CChar($0) }
			let result = temporaryDirectoryTemplate.withUnsafeMutableBufferPointer { (inout template: UnsafeMutableBufferPointer<CChar>) -> UnsafeMutablePointer<CChar> in
				return mkdtemp(template.baseAddress)
			}

			if result == nil {
				return .failure(.taskError(.posixError(errno)))
			}

			let temporaryPath = temporaryDirectoryTemplate.withUnsafeBufferPointer { (ptr: UnsafeBufferPointer<CChar>) -> String in
				return String.fromCString(ptr.baseAddress)!
			}

			return .success(temporaryPath)
		}
		.map { NSURL.fileURLWithPath($0, isDirectory: true) }
		.flatMap(.merge) { directoryURL in
			return unzip(archive: fileURL, to: directoryURL)
				.then(SignalProducer(value: directoryURL))
		}
}
