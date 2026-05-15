//
//  MLModels.swift
//  MicroCode
//
//  Enterprise ML Training Types & Models
//  Created by Tirawat Nantamas | Dotmini Software
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import Foundation
import CoreML
import SwiftUI

// MARK: - Dataset

struct MLDataset: Identifiable {
    let id = UUID()
    let name: String
    let trainPath: URL
    let validationPath: URL?
    let testPath: URL?
    let classes: [String]
    let imageCount: [String: Int]
    
    var totalImages: Int {
        imageCount.values.reduce(0, +)
    }
}

// MARK: - Pretrained Models

struct PretrainedModel: Identifiable, Hashable {
    let id: String
    let name: String
    let architecture: String
    let description: String
    let inputSize: CGSize
    let parameterCount: Int
    let icon: String
    let category: ModelCategory
    
    enum ModelCategory: String, CaseIterable {
        case lightweight = "Lightweight"
        case balanced = "Balanced"
        case highAccuracy = "High Accuracy"
        case cuttingEdge = "Cutting Edge"
    }
    
    static let availableModels: [PretrainedModel] = [
        // Lightweight Models
        PretrainedModel(
            id: "mobilenet_v2",
            name: "MobileNetV2",
            architecture: "MobileNet",
            description: "Lightweight model optimized for mobile devices. Fast training and inference with minimal memory footprint.",
            inputSize: CGSize(width: 224, height: 224),
            parameterCount: 3_500_000,
            icon: "iphone",
            category: .lightweight
        ),
        PretrainedModel(
            id: "squeezenet",
            name: "SqueezeNet",
            architecture: "SqueezeNet",
            description: "Ultra-compact model for rapid prototyping. Best when model size is critical.",
            inputSize: CGSize(width: 227, height: 227),
            parameterCount: 1_250_000,
            icon: "bolt.fill",
            category: .lightweight
        ),
        PretrainedModel(
            id: "mobilenet_v3",
            name: "MobileNetV3-Small",
            architecture: "MobileNet",
            description: "Latest MobileNet with Neural Architecture Search. Optimized for edge deployment.",
            inputSize: CGSize(width: 224, height: 224),
            parameterCount: 2_500_000,
            icon: "cpu",
            category: .lightweight
        ),
        
        // Balanced Models
        PretrainedModel(
            id: "efficientnet_b0",
            name: "EfficientNet-B0",
            architecture: "EfficientNet",
            description: "Balanced efficiency and accuracy using compound scaling. Great for general use.",
            inputSize: CGSize(width: 224, height: 224),
            parameterCount: 5_300_000,
            icon: "gauge",
            category: .balanced
        ),
        PretrainedModel(
            id: "efficientnet_v2_s",
            name: "EfficientNetV2-S",
            architecture: "EfficientNetV2",
            description: "Improved training speed with progressive learning. State-of-the-art efficiency.",
            inputSize: CGSize(width: 384, height: 384),
            parameterCount: 21_500_000,
            icon: "gauge.with.needle",
            category: .balanced
        ),
        PretrainedModel(
            id: "regnet_y_4gf",
            name: "RegNet-Y-4GF",
            architecture: "RegNet",
            description: "Designed network with optimized design space. Excellent speed/accuracy trade-off.",
            inputSize: CGSize(width: 224, height: 224),
            parameterCount: 20_600_000,
            icon: "rectangle.3.group",
            category: .balanced
        ),
        
        // High Accuracy Models
        PretrainedModel(
            id: "resnet50",
            name: "ResNet-50",
            architecture: "ResNet",
            description: "Deep residual network with 50 layers. Proven high accuracy for complex classification tasks.",
            inputSize: CGSize(width: 224, height: 224),
            parameterCount: 25_600_000,
            icon: "square.stack.3d.up",
            category: .highAccuracy
        ),
        PretrainedModel(
            id: "resnet101",
            name: "ResNet-101",
            architecture: "ResNet",
            description: "Deeper variant with 101 layers. Higher accuracy for demanding applications.",
            inputSize: CGSize(width: 224, height: 224),
            parameterCount: 44_500_000,
            icon: "square.stack.3d.up.fill",
            category: .highAccuracy
        ),
        PretrainedModel(
            id: "convnext_tiny",
            name: "ConvNeXt-Tiny",
            architecture: "ConvNeXt",
            description: "Modernized ConvNet competing with Transformers. Strong baseline for high accuracy.",
            inputSize: CGSize(width: 224, height: 224),
            parameterCount: 28_600_000,
            icon: "square.grid.3x3.fill",
            category: .highAccuracy
        ),
        
        // Cutting Edge Models
        PretrainedModel(
            id: "vit_b_16",
            name: "ViT-B/16",
            architecture: "Vision Transformer",
            description: "Vision Transformer with 16x16 patch size. State-of-the-art with ample training data.",
            inputSize: CGSize(width: 224, height: 224),
            parameterCount: 86_000_000,
            icon: "wand.and.stars",
            category: .cuttingEdge
        ),
        PretrainedModel(
            id: "swin_tiny",
            name: "Swin-Tiny",
            architecture: "Swin Transformer",
            description: "Shifted window Transformer. Efficient self-attention with hierarchical representation.",
            inputSize: CGSize(width: 224, height: 224),
            parameterCount: 28_300_000,
            icon: "window.horizontal",
            category: .cuttingEdge
        ),
        PretrainedModel(
            id: "deit_small",
            name: "DeiT-Small",
            architecture: "Data-efficient Image Transformer",
            description: "Transformer trained efficiently on ImageNet alone. No external data required.",
            inputSize: CGSize(width: 224, height: 224),
            parameterCount: 22_100_000,
            icon: "sparkles",
            category: .cuttingEdge
        )
    ]
}

// MARK: - Training Configuration

enum Optimizer: String, CaseIterable, Codable {
    case adam = "Adam"
    case adamW = "AdamW"
    case sgd = "SGD"
    case sgdMomentum = "SGD + Momentum"
    case rmsprop = "RMSprop"
    case adagrad = "Adagrad"
}

enum LRScheduler: String, CaseIterable, Codable {
    case none = "None"
    case stepDecay = "Step Decay"
    case exponentialDecay = "Exponential Decay"
    case cosineAnnealing = "Cosine Annealing"
    case warmupCosine = "Warmup + Cosine"
    case oneCycle = "One Cycle"
    case reduceOnPlateau = "Reduce on Plateau"
}

enum RegularizationType: String, CaseIterable, Codable {
    case none = "None"
    case l1 = "L1 (Lasso)"
    case l2 = "L2 (Ridge)"
    case l1l2 = "Elastic Net (L1+L2)"
    case dropout = "Dropout"
}

struct DataAugmentation: Codable {
    var randomRotation: Bool = true
    var randomFlip: Bool = true
    var randomCrop: Bool = false
    var colorJitter: Bool = false
    var randomScale: Bool = false
    var randomErasing: Bool = false
    var mixup: Bool = false
    var cutmix: Bool = false
}

struct TrainingConfig: Codable {
    // Basic Hyperparameters
    var learningRate: Double = 0.001
    var batchSize: Int = 32
    var epochs: Int = 10
    var optimizer: Optimizer = .adam
    
    // Learning Rate Scheduling
    var scheduler: LRScheduler = .none
    var warmupEpochs: Int = 0
    var minLearningRate: Double = 0.00001
    
    // Regularization
    var regularization: RegularizationType = .none
    var regularizationStrength: Double = 0.0001
    var dropoutRate: Double = 0.5
    
    // Data Augmentation
    var augmentation: DataAugmentation = DataAugmentation()
    
    // Training Strategy
    var transferLearning: Bool = true
    var freezeLayers: Int = 0
    var earlyStoppingPatience: Int = 5
    
    // Advanced
    var gradientClipping: Bool = false
    var gradientClipValue: Double = 1.0
    var mixedPrecision: Bool = false
    var labelSmoothing: Double = 0.0
    
    // Validation
    var validationSplit: Double = 0.2
    var crossValidationFolds: Int = 0
}

// MARK: - Training Progress

struct TrainingProgress {
    var currentEpoch: Int = 0
    var totalEpochs: Int
    var currentBatch: Int = 0
    var totalBatches: Int = 0
    var trainingLoss: Double = 0.0
    var trainingAccuracy: Double = 0.0
    var validationLoss: Double = 0.0
    var validationAccuracy: Double = 0.0
    var timePerEpoch: TimeInterval = 0.0
    var elapsedTime: TimeInterval = 0.0
    var learningRateCurrent: Double = 0.0
    
    var eta: TimeInterval {
        let remainingEpochs = totalEpochs - currentEpoch
        return timePerEpoch * Double(remainingEpochs)
    }
    
    var percentComplete: Double {
        guard totalEpochs > 0 else { return 0 }
        return Double(currentEpoch) / Double(totalEpochs)
    }
}

struct EpochMetrics: Identifiable {
    let id = UUID()
    let epoch: Int
    let trainingLoss: Double
    let trainingAccuracy: Double
    let validationLoss: Double
    let validationAccuracy: Double
    let learningRate: Double
    let epochDuration: TimeInterval
    
    init(epoch: Int, trainingLoss: Double, trainingAccuracy: Double, validationLoss: Double, validationAccuracy: Double, learningRate: Double = 0.001, epochDuration: TimeInterval = 0) {
        self.epoch = epoch
        self.trainingLoss = trainingLoss
        self.trainingAccuracy = trainingAccuracy
        self.validationLoss = validationLoss
        self.validationAccuracy = validationAccuracy
        self.learningRate = learningRate
        self.epochDuration = epochDuration
    }
}

// MARK: - Export Formats

enum ExportFormat: String, CaseIterable {
    case mlmodel = "CoreML Model"
    case mlpackage = "CoreML Package"
    case onnx = "ONNX"
    case onnxQuantized = "ONNX (INT8 Quantized)"
    case tflite = "TensorFlow Lite"
    case tfSavedModel = "TensorFlow SavedModel"
    case pytorch = "PyTorch"
    case torchScript = "TorchScript"
    
    var fileExtension: String {
        switch self {
        case .mlmodel: return "mlmodel"
        case .mlpackage: return "mlpackage"
        case .onnx, .onnxQuantized: return "onnx"
        case .tflite: return "tflite"
        case .tfSavedModel: return "zip"
        case .pytorch: return "pt"
        case .torchScript: return "pt"
        }
    }
    
    var displayName: String {
        rawValue
    }
    
    var icon: String {
        switch self {
        case .mlmodel, .mlpackage: return "apple.logo"
        case .onnx, .onnxQuantized: return "cube.transparent"
        case .tflite, .tfSavedModel: return "t.square"
        case .pytorch, .torchScript: return "flame"
        }
    }
    
    var color: Color {
        switch self {
        case .mlmodel, .mlpackage: return .blue
        case .onnx, .onnxQuantized: return .purple
        case .tflite, .tfSavedModel: return .orange
        case .pytorch, .torchScript: return .red
        }
    }
    
    var description: String {
        switch self {
        case .mlmodel: return "Native format for Apple platforms (iOS, macOS, tvOS, watchOS)"
        case .mlpackage: return "Modern CoreML format with better tooling support"
        case .onnx: return "Open format for interoperability across frameworks"
        case .onnxQuantized: return "Quantized ONNX for reduced size and faster inference"
        case .tflite: return "Optimized for mobile and embedded devices"
        case .tfSavedModel: return "TensorFlow's default serving format"
        case .pytorch: return "PyTorch checkpoint format"
        case .torchScript: return "Serialized PyTorch for production deployment"
        }
    }
}

// MARK: - Training State

enum TrainingState: Equatable {
    case idle
    case preparing
    case training
    case paused
    case completed
    case failed(Error)
    
    static func == (lhs: TrainingState, rhs: TrainingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.preparing, .preparing),
             (.training, .training),
             (.paused, .paused),
             (.completed, .completed):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
    
    var isActive: Bool {
        switch self {
        case .training, .preparing: return true
        default: return false
        }
    }
    
    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .preparing: return "Preparing..."
        case .training: return "Training"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
    
    var color: Color {
        switch self {
        case .idle: return .secondary
        case .preparing: return .orange
        case .training: return .green
        case .paused: return .yellow
        case .completed: return .blue
        case .failed: return .red
        }
    }
}

// MARK: - Validation Results

struct ValidationResults {
    var accuracy: Double = 0.0
    var precision: Double = 0.0
    var recall: Double = 0.0
    var f1Score: Double = 0.0
    var confusionMatrix: [[Int]] = []
    var classAccuracies: [String: Double] = [:]
    var rocAuc: Double = 0.0
}

// MARK: - Model Metadata

struct TrainedModelMetadata {
    let trainingDate: Date
    let datasetName: String
    let baseModel: String
    let epochs: Int
    let finalAccuracy: Double
    let finalLoss: Double
    let trainingDuration: TimeInterval
    let hyperparameters: TrainingConfig
}
