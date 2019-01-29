//
//  AudioConverterListener.swift
//  Pods-SwiftAudioPlayer_Example
//
//  Created by Tanha Kabir on 2019-01-29.
//

import Foundation
import AVFoundation
import AudioToolbox

func ConverterListener(_ converter: AudioConverterRef, _ packetCount: UnsafeMutablePointer<UInt32>, _ ioData: UnsafeMutablePointer<AudioBufferList>, _ outPacketDescriptions: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?, _ context: UnsafeMutableRawPointer?) -> OSStatus {
    let selfAudioConverter = Unmanaged<AudioConverter>.fromOpaque(context!).takeUnretainedValue()
    
    guard let parser = selfAudioConverter.parser else {
        Log.monitor("ReaderMissingParserError")
        return ReaderMissingParserError
    }
    
    guard let fileAudioFormat = parser.fileAudioFormat else {
        Log.monitor("ReaderMissingSourceFormatError")
        return ReaderMissingSourceFormatError
    }
    
    var audioPacketFromParser:(AudioStreamPacketDescription?, Data)?
    do {
        audioPacketFromParser = try parser.pullPacket(atIndex: selfAudioConverter.currentAudioPacketIndex)
        Log.debug("received packet from parser at index: \(selfAudioConverter.currentAudioPacketIndex)")
    } catch ParserError.notEnoughDataForReader {
        return ReaderNotEnoughDataError
    } catch ParserError.readerAskingBeyondEndOfFile {
        //On output, the number of packets of audio data provided for conversion,
        //or 0 if there is no more data to convert.
        packetCount.pointee = 0
        return ReaderReachedEndOfDataError
    } catch {
        return ReaderShouldNotHappenError
    }
    
    guard let audioPacket = audioPacketFromParser else {
        return ReaderShouldNotHappenError
    }
    
    // Copy data over (note we've only processing a single packet of data at a time)
    var packet = audioPacket.1
    let packetByteCount = packet.count //this is not the count of an array
    ioData.pointee.mNumberBuffers = 1
    ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer.allocate(byteCount: packetByteCount, alignment: 0)
    _ = packet.withUnsafeMutableBytes({ (bytes: UnsafeMutablePointer<UInt8>) in
        memcpy((ioData.pointee.mBuffers.mData?.assumingMemoryBound(to: UInt8.self))!, bytes, packetByteCount)
    })
    ioData.pointee.mBuffers.mDataByteSize = UInt32(packetByteCount)
    
    // Handle packet descriptions for compressed formats (MP3, AAC, etc)
    let fileFormatDescription = fileAudioFormat.streamDescription.pointee
    if fileFormatDescription.mFormatID != kAudioFormatLinearPCM {
        if outPacketDescriptions?.pointee == nil {
            outPacketDescriptions?.pointee = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
        }
        outPacketDescriptions?.pointee?.pointee.mDataByteSize = UInt32(packetByteCount)
        outPacketDescriptions?.pointee?.pointee.mStartOffset = 0
        outPacketDescriptions?.pointee?.pointee.mVariableFramesInPacket = 0
    }
    
    packetCount.pointee = 1
    
    //we've successfully given a packet to the LPCM buffer now we can process the next audio packet
    selfAudioConverter.currentAudioPacketIndex = selfAudioConverter.currentAudioPacketIndex + 1
    
    return noErr
}
