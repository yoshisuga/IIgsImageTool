//
//  main.swift
//  IIgsImageTool
//
//  Created by Yoshi Sugawara on 1/3/23.
//

import ArgumentParser
import Foundation
import OrderedCollections
import SwiftImage

struct IIgsColor: Hashable {
  let red: UInt8
  let green: UInt8
  let blue:UInt8
  
  var hex: String {
    String(format: "%02X%1X%1X", red, green, blue)
  }
}

struct IIgsPalette {
  private var allColors = OrderedSet<IIgsColor>()
  
  var colors: [IIgsColor] {
    Array(allColors.prefix(16))
  }
  
  mutating func addColor(_ color: IIgsColor) {
    allColors.append(color)
  }
  
  var asmSetColors: String {
    var asm = ""
    for (index, color) in colors.enumerated() {
      var label = ""
      if index == 0 {
        label = "SetupPalette    "
      } else {
        label = "                "
      }
      let offset = String(format: "%04X", index)
      asm.append("""
\(label) lda #$\(color.hex)
                 ldx #$\(offset)
                 jsr SetPaletteColor

""")
    }
    asm.append("""
                 rts
""")
    return asm
  }
  
  static let asmSetPaletteSubroutine = """
****************************************
* A= color values (0RGB)               *
* X= color/palette offset              *
*   (0-F = pal0, 10-1F = pal1, etc.)   *
****************************************
SetPaletteColor  pha                         ;save accumulator
                 txa
                 asl                         ;X*2 = real offset to color table
                 tax
                 pla
                 stal  $E19E00,x             ;palettes are stored from $E19E00-FF
                 rts                         ;yup, that's it
"""
}

struct IIgsImageTool: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Tool to convert png images to Apple IIGS assembly code"
  )
  
  @Argument(help: "The path to the image file")
  private var imagePath: String
  
  @Argument(help: "The label to reference the image in assembly code (default = PIC). Limited to 16 characters long, and will get truncated if longer.")
  private var label: String?
  
  private var resolvedLabel: String {
    guard let label else {
      return "PIC"
    }
    if label.count <= 16 {
      return label
    }
    return String(label.prefix(16))
  }
  
  func run() throws {
    guard let image = Image<RGBA<UInt8>>(contentsOfFile: imagePath) else {
      fatalError("Could not read image from \(imagePath)")
    }
    var palette = IIgsPalette()
    var rawHex = ""
    for pixel in image {
      // Bit-depth conversion from: http://threadlocalmutex.com/?p=48
      let red4bit = UInt8((Int(pixel.red) * 15 + 135) >> 8)
      let blue4bit = UInt8((Int(pixel.blue) * 15 + 135) >> 8)
      let green4bit = UInt8((Int(pixel.green) * 15 + 135) >> 8)
      let color = IIgsColor(red: red4bit, green: green4bit, blue: blue4bit)
      palette.addColor(color)
      let colorIndex: Array<IIgsColor>.Index = {
        guard let index = palette.colors.firstIndex(of: color) else {
          return 0
        }
        return index
      }()
      rawHex.append(String(format: "%1X",colorIndex))
    }
    
    var asm = ""
    var buffer = ""
    var output = ""
    
    let numWritesPerLine = String(format: "%04X",image.width/4)
    let totalWrites = String(format: "%04X",rawHex.count/4)

    let asmDraw = """
* Draw \(resolvedLabel) at screen offset X
]curpos          ds    2
]totalWritesLeft ds    2
]lineWritesLeft  ds    2


DRAW\(resolvedLabel)    stx ]curpos
                        lda #$\(totalWrites)        ; number of writes: \(rawHex.count/4)
                        sta ]totalWritesLeft
                        lda #$\(numWritesPerLine)   ; number of writes per line: \(image.width/4)
                        stal ]lineWritesLeft
                        ldy #$0000                  ; Y is current graphic offset of write

:drawLoop               lda \(resolvedLabel),Y      ; load graphic data with graphical offset
                        ldx ]curpos
                        stal $e12000,x              ; write to screen

                        dec ]totalWritesLeft        ; decrement number of writes left to do
                        beq :drawFinish

                        iny
                        iny
                        inc ]curpos
                        inc ]curpos
                        dec ]lineWritesLeft         ; decrement number of writes left on this line
                        beq :nextline
                        jmp :drawLoop

:nextline               lda ]curpos
                        adc #$A0                    ; go to next line
                        sbc #\(image.width/2)       ; number of bytes written per line (2 pixels/byte)
                        sta ]curpos
                        lda #$\(numWritesPerLine)   ; reset number of writes per line
                        sta ]lineWritesLeft
                        jmp :drawLoop

:drawFinish             rts
"""
    
    for (index,ch) in rawHex.enumerated() {
      output.append(ch)
      buffer.append(ch)
      if (index + 1) % image.width == 0 {
        output.append("\n")
      }
      if (index + 1) % 20 == 0 {
        if asm.isEmpty {
          asm.append("\(resolvedLabel)")
        }
        asm.append("        hex \(buffer)\n")
        buffer = ""
      }
    }
    if !buffer.isEmpty {
      asm.append("        hex \(buffer)\n")
    }
    

    print("""
* Merlin-compatible ASM generated by IIgsImageTool
*
* Use cadius INDENTFILE to fix the indentation on this file
*
* Initialize SHR graphics mode and set the scanline control bytes to palette 0 before
* calling DRAW\(resolvedLabel) to draw the graphics

\(asmDraw)

\(palette.asmSetColors)

\(IIgsPalette.asmSetPaletteSubroutine)

\(asm)
""")    
  }
}

IIgsImageTool.main()
