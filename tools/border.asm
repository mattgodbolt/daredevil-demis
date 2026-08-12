\ Measure the gap between the vsync interrupt and the first displayed line.
\ Flood the palette red at vsync, hold it for N scanlines, then black. The red
\ band that appears on screen is N minus the border, so border = N - height.
N_LINES = 200
IRQ1V = &0204
ORG &1900
.start
    LDA #22: JSR &FFEE
    LDA #5:  JSR &FFEE
    LDA #10: STA &FE00
    LDA #32: STA &FE01
    SEI
    LDA IRQ1V: STA old: LDA IRQ1V+1: STA old+1
    LDA #LO(irq): STA IRQ1V
    LDA #HI(irq): STA IRQ1V+1
    CLI
.loop
    LDA count
.spin
    CMP count
    BEQ spin
    LDA #1: JSR mark            \ red, starting at the vsync interrupt
    LDX #N_LINES
.wait
    LDY #25                     \ ~1 scanline
.w2 DEY
    BNE w2
    DEX
    BNE wait
    LDA #0: JSR mark            \ back to black
    JMP loop
.mark
    EOR #7
    STA col
    LDX #15
.ml TXA
    ASL A: ASL A: ASL A: ASL A
    ORA col
    STA &FE21
    DEX
    BPL ml
    RTS
.irq
    LDA &FE4D
    AND #2
    BEQ chain
    INC count
.chain
    JMP (old)
.old   EQUW 0
.count EQUB 0
.col   EQUB 0
SAVE "Code", start, P%, start
