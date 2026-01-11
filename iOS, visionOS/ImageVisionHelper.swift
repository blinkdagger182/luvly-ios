//
//  ImageVisionHelper.swift
//  LockInNote
//

import Foundation
import CoreImage
import Vision
import UIKit

struct ImageVisionHelper {
    
    func removeBackground(from image: UIImage) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: ciImage)
        
        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform vision request: \(error)")
            return nil
        }
        
        guard let result = request.results?.first else {
            print("No subject observations found")
            return nil
        }
        
        do {
            let maskedImage = try result.generateMaskedImage(
                ofInstances: result.allInstances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let ciMasked = CIImage(cvPixelBuffer: maskedImage)
            
            guard let cgImage = CIContext().createCGImage(ciMasked, from: ciMasked.extent) else {
                return nil
            }
            
            return UIImage(cgImage: cgImage)
        } catch {
            print("Failed to generate masked image: \(error)")
            return nil
        }
    }
}
