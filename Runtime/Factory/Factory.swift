// MIT License
//
// Copyright (c) 2017 Wesley Wickwire
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation


public func createInstance<T>() throws -> T {
    if let value = try createInstance(of: T.self) as? T {
        return value
    }
    
    throw RuntimeError.unableToBuildType(type: T.self)
}

public func createInstance(of type: Any.Type) throws -> Any {
    
    if let defaultConstructor = type as? DefaultConstructor.Type {
        return defaultConstructor.init()
    }
    
    let kind = Kind(type: type)
    
    #if os(iOS) // does not work on macOS or Linux
        switch kind {
        case .struct:
            return try buildStruct(type: type)
        case .class:
            return try buildClass(type: type)
        default:
            throw RuntimeError.unableToBuildType(type: type)
        }
    #else // class does not work on macOS or Linux
        switch kind {
        case .struct:
            return try buildStruct(type: type)
        default:
            throw RuntimeError.unableToBuildType(type: type)
        }
    #endif
}

func buildStruct(type: Any.Type) throws -> Any {
    let info = try typeInfo(of: type)
    let pointer = UnsafeMutableRawPointer.allocate(bytes: info.size, alignedTo: info.alignment)
    defer { pointer.deallocate(bytes: info.size, alignedTo: info.alignment) }
    try setProperties(typeInfo: info, pointer: pointer)
    return getters(type: type).get(from: pointer)
}

#if os(iOS) // does not work on macOS or Linux
    func buildClass(type: Any.Type) throws -> Any {
        let info = try typeInfo(of: type)
        if let type = type as? AnyClass, var value = class_createInstance(type, 0) {
            try withClassValuePointer(of: &value) { pointer in
                try setProperties(typeInfo: info, pointer: pointer)
                let header = pointer.assumingMemoryBound(to: ClassHeader.self)
                header.pointee.strongRetainCounts = 2
            }
            return value
        }
        throw RuntimeError.unableToBuildType(type: type)
    }
#endif

func setProperties(typeInfo: TypeInfo, pointer: UnsafeMutableRawPointer) throws {
    for property in typeInfo.properties {
        let value = try defaultValue(of: property.type)
        let valuePointer = pointer.advanced(by: property.offset)
        let sets = setters(type: property.type)
        sets.set(value: value, pointer: valuePointer)
    }
}


func defaultValue(of type: Any.Type) throws -> Any {
    
    if let constructable = type as? DefaultConstructor.Type {
        return constructable.init()
    } else if let isOptional = type as? ExpressibleByNilLiteral.Type {
        return isOptional.init(nilLiteral: ())
    }
    
    return try createInstance(of: type)
}
