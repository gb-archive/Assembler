//
//  Linker.swift
//  Assembler
//
//  Created by Ulrik Damm on 08/09/2016.
//  Copyright © 2016 Ufd.dk. All rights reserved.
//

enum Opcode : CustomStringConvertible {
	case byte(UInt8)
	case word(UInt16)
	case label(String)
	case expression(Expression)
	
	var description : String {
		switch self {
		case .byte(let b): return String(b, radix: 16)
		case .word(let w): return String(w, radix: 16)
		case .label(let name): return name
		case .expression(let expr): return expr.description
		}
	}
	
	var byteLength : Int {
		switch self {
		case .byte(_): return 1
		case .word(_): return 2
		case .label(_): return 2
		case .expression(_): return 2
		}
	}
	
	static func bytesFrom16bit(_ value : Int) throws -> [Opcode] {
		let n16 = try UInt16.fromInt(value: value)
		return [.byte(n16.lsb), .byte(n16.msb)]
	}
}

extension Opcode : Equatable {
	static func ==(lhs : Opcode, rhs : Opcode) -> Bool {
		switch (lhs, rhs) {
		case (.byte(let nl), .byte(let nr)) where nl == nr: return true
		case (.word(let nl), .word(let nr)) where nl == nr: return true
		case (.label(let sl), .label(let sr)) where sl == sr: return true
		case (.expression(let el), .expression(let er)) where el == er: return true
		case _: return false
		}
	}
}

struct Linker {
	struct Block {
		let name : String
		let origin : Int?
		let data : [Opcode]
	}
	
	struct Allocation {
		let start : Int
		let length : Int
		let blockId : Int
	}
	
	let blocks : [Block]
	let allocations : [Allocation]
	
	init(blocks : [Block]) {
		self.blocks = blocks
		self.allocations = Linker.createAllocations(blocks: blocks)
	}
	
	func link() throws -> [UInt8] {
		let size = calculateBinarySize()
		var data = Array<UInt8>(repeating: 0, count: size)
		
		for allocation in allocations {
			var offset = 0
			for byte in blocks[allocation.blockId].data {
				switch byte {
				case .byte(let n):
					data[allocation.start + offset] = n
					offset += 1
				case .word(let n):
					data[allocation.start + offset] = n.lsb
					data[allocation.start + offset + 1] = n.msb
					offset += 2
				case .label(let name):
					if let start = blockStart(name: name) {
						let n16 = try UInt16.fromInt(value: start)
						data[allocation.start + offset] = n16.lsb
						data[allocation.start + offset + 1] = n16.msb
						offset += 2
					} else {
						throw ErrorMessage("Unknown label ’\(name)‘")
					}
				case .expression(let expr):
					let mapped = try expr.mapSubExpressions(map: replaceExpressionLabelValue)
					let reduced = mapped.reduce()
					guard case .value(let value) = reduced else {
						throw ErrorMessage("Invalid value `\(reduced)`")
					}
					
					let n16 = try UInt16.fromInt(value: value)
					data[allocation.start + offset] = n16.lsb
					data[allocation.start + offset + 1] = n16.msb
					offset += 2
				}	
			}
		}
		
		return data
	}
	
	func replaceExpressionLabelValue(expression : Expression) throws -> Expression {
		switch expression {
		case .constant(let name):
			guard let location = blockStart(name: name) else {
				throw ErrorMessage("Unknown label `\(name)`")
			}
			return .value(location)
		case _: return expression
		}
	}
	
	static func createAllocations(blocks : [Block]) -> [Allocation] {
		var allocations : [Allocation] = []
		
		for (blockId, block) in blocks.enumerated() {
			let start = block.origin
				?? allocations.last.map { $0.start + $0.length }
				?? 0
			let length = blockLength(block: block)
			let allocation = Allocation(start: start, length: length, blockId: blockId)
			allocations.append(allocation)
		}
		
		return allocations
	}
	
	static func blockLength(block : Block) -> Int {
		return block.data.map { $0.byteLength }.reduce(0, +)
	}
	
	func calculateBinarySize() -> Int {
		var furthestEnd = 0
		
		for allocation in allocations {
			let end = allocation.start + allocation.length
			
			if end > furthestEnd {
				furthestEnd = end
			}
		}
		
		return furthestEnd
	}
	
	func blockStart(name : String) -> Int? {
		for allocation in allocations {
			let block = blocks[allocation.blockId]
			if block.name == name {
				return allocation.start
			}
		}
		
		return nil
	}
}
