//
//  ViewController.swift
//  CombinedSoundWave
//
//  Created by Joseph Janizek on 4/14/20.
//  Copyright © 2020 Joseph Janizek. All rights reserved.
//

import UIKit
import AVFoundation
import Foundation
import Accelerate
import AudioKit

class ViewController: UIViewController {
    
    var engine = AVAudioEngine()
    var distortion = AVAudioUnitDistortion()
    var reverb = AVAudioUnitReverb()
    var audioBuffer = AVAudioPCMBuffer()
    var outputFile = AVAudioFile()
    var delay = AVAudioUnitDelay()
    var mic = AKMicrophone()
    var oscillator = AKOscillator()
    
    @IBOutlet weak var mainLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
        
    func getBufferFloats(pcmBuffer: AVAudioPCMBuffer) -> [Float]? {
        if let floatChannelData = pcmBuffer.floatChannelData {
            let frameLength = Int(pcmBuffer.frameLength)
            let stride = pcmBuffer.stride
            var result: [Float] = Array(repeating:0.0, count: frameLength)
            
            for sampleIndex in 0..<frameLength {
                result[sampleIndex] = floatChannelData[1][sampleIndex * stride]
            }
            
            return result
        } else {
            print("format not in Float")
            return nil
        }
    }
    
    func fftTransform(buffer: AVAudioPCMBuffer) -> [Float] {
      let frameCount = buffer.frameLength
      let log2n = UInt(round(log2(Double(frameCount))))
      let bufferSizePOT = Int(1 << log2n)
      let inputCount = bufferSizePOT / 2
      let fftSetup = vDSP_create_fftsetup(log2n, Int32(kFFTRadix2))

      let floatBuffer = getBufferFloats(pcmBuffer: buffer)

      var realp = [Float](floatBuffer!)
      var imagp = [Float](repeating: 0, count: inputCount)
      var output = DSPSplitComplex(realp: &realp, imagp: &imagp)

      vDSP_fft_zrip(fftSetup!, &output, 1, log2n, FFTDirection(FFT_FORWARD))

      var magnitudes = [Float](repeating: 0.0, count: inputCount)
      vDSP_zvmags(&output, 1, &magnitudes, 1, vDSP_Length(inputCount))

      var normalizedMagnitudes = [Float](repeating: 0.0, count: inputCount)
      vDSP_vsmul(sqrtq(magnitudes), 1, [2.0 / Float(inputCount)],
        &normalizedMagnitudes, 1, vDSP_Length(inputCount))

      vDSP_destroy_fftsetup(fftSetup)

      return normalizedMagnitudes
    }
    
    func sqrtq(_ x: [Float]) -> [Float] {
      var results = [Float](repeating: 0.0, count: x.count)
      vvsqrtf(&results, x, [Int32(x.count)])

      return results
    }
    
    func initializeAudioEngine() {
        print("initializing")
        engine.stop()
        engine.reset()
        engine = AVAudioEngine()
        
        do {
            
            try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord)
            try AVAudioSession.sharedInstance().setActive(true)
            
        } catch {

            assertionFailure("AVAudioSession setup error: \(error)")
        }

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        
        engine.connect(input, to: engine.mainMixerNode, format: format)

        try! engine.start()
        
        let mixer = engine.mainMixerNode
        let outputFormat = mixer.outputFormat(forBus: 0)
        print(outputFormat)

        mixer.installTap(onBus: 0, bufferSize: 1024, format: outputFormat, block:
            { (buffer: AVAudioPCMBuffer!, time: AVAudioTime!) in
                let current_fft = self.fftTransform(buffer: buffer)
                let downshift = current_fft[764]+current_fft[765]+current_fft[766]+current_fft[767]
                let upshift = current_fft[769]+current_fft[770]+current_fft[771]+current_fft[772]
                // commented out the working values for laptop
//                let downshift = current_fft[835] + current_fft[834] + current_fft[833] + current_fft[832]
//                let upshift = current_fft[837] + current_fft[838] + current_fft[839] + current_fft[840]
                let ratio = upshift/downshift
//                print(ratio)
//                print(current_fft.count)
//                print(current_fft[833...840])
//                print(current_fft[834...838])
                print(vDSP.indexOfMaximum(current_fft[200...1024]))
                if ratio > 4 {
                    print("push")
                    DispatchQueue.main.async {
                        self.pushLabel()
                    }
                }
                if ratio < 0.2 {
                    print("pull")
                    DispatchQueue.main.async {
                        self.pullLabel()
                    }
                }

        })
    }
    
    func pushLabel() {
        self.mainLabel.text = "PUSH"
    }
    
    func pullLabel() {
        self.mainLabel.text = "PULL"
    }
    @IBAction func startDetection(_ sender: Any) {

        initMicrophone()
    }
    
    func initMicrophone() {
        
        AudioKit.output = AKMixer(oscillator)
        do{
            try AudioKit.start()
        } catch{
            
        }
        oscillator.amplitude = 1
        oscillator.frequency = 18000
        oscillator.start()

        // Facultative, allow to set the sampling rate of the microphone
        AKSettings.sampleRate = 44100

        // Link the microphone note to the output of AudioKit with a volume of 0.
//        AudioKit.output = AKBooster(mic, gain:0)

        // Start AudioKit engine
        try! AudioKit.start()

        // Add a tap to the microphone
        mic?.avAudioNode.installTap(onBus: 0, bufferSize: 1024, format: nil, block:
                    { (buffer: AVAudioPCMBuffer!, time: AVAudioTime!) in
                        let current_fft = self.fftTransform(buffer: buffer)
                        let downshift = current_fft[835] + current_fft[834] + current_fft[833] + current_fft[832]
                        let upshift = current_fft[837] + current_fft[838] + current_fft[839] + current_fft[840]
                        let ratio = upshift/downshift

                        if ratio > 4 {
                            print("push")
                            DispatchQueue.main.async {
                                self.pushLabel()
                            }
                        }
                        if ratio < 0.23 {
                            print("pull")
                            DispatchQueue.main.async {
                                self.pullLabel()
                            }
                        }

                })

}
}
