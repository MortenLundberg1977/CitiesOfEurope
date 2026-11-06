// ==============================================================
// Cities of Europe: what differs from World Cities. src/game.asm is the
// same in both projects.
// ==============================================================

.const FLAG_HINT = 1           // 1: the first hint shows the country's flag
                               // 0: it shows the country's name

// the text title, shown when there is no title picture
.macro title_text() {
        .text "** CITIES OF EUROPE **"
        .byte $0D, $0D
        .text "10 CITIES ARE MARKED ON THE MAP. PICK"
        .byte $0D
        .text "THE RIGHT ONE WITH KEYS 1-3. H GIVES"
        .byte $0D
        .text "A HINT: THE FLAG, THEN 50/50. FEWER"
        .byte $0D
        .text "HINTS AND QUICK ANSWERS SCORE MORE."
        .byte $0D, $0D
        .text "PRESS SPACE TO START, S FOR STATS"
        .byte 0
}

// Title music: Ode to Joy (Beethoven, 9th symphony; the European anthem).
// Note numbers count semitones from C2 = 1; ticks are 1/60 s.
.const C3 = 13
.const D3 = 15
.const E3 = 17
.const F3 = 18
.const G3 = 20
.const A3 = 22
.const B3 = 24
.const C4 = 25
.const D4 = 27
.const E4 = 29
.const F4 = 30
.const G4 = 32
.const G2 = 8
.const Q = 24                  // a quarter note
.const H = 48
.const DQ = 36
.const E8 = 12

.macro tune_melody_data() {
        // phrase 1: E E F G | G F E D | C C D E | E. D D
        .byte E4,Q, E4,Q, F4,Q, G4,Q,  G4,Q, F4,Q, E4,Q, D4,Q
        .byte C4,Q, C4,Q, D4,Q, E4,Q,  E4,DQ, D4,E8, D4,H
        // phrase 2: ... | D. C C
        .byte E4,Q, E4,Q, F4,Q, G4,Q,  G4,Q, F4,Q, E4,Q, D4,Q
        .byte C4,Q, C4,Q, D4,Q, E4,Q,  D4,DQ, C4,E8, C4,H
        // phrase 3: D D E C | D EF E C | D EF E D | C D G
        .byte D4,Q, D4,Q, E4,Q, C4,Q,  D4,Q, E4,E8, F4,E8, E4,Q, C4,Q
        .byte D4,Q, E4,E8, F4,E8, E4,Q, D4,Q,  C4,Q, D4,Q, G3,H
        // phrase 4 = phrase 2
        .byte E4,Q, E4,Q, F4,Q, G4,Q,  G4,Q, F4,Q, E4,Q, D4,Q
        .byte C4,Q, C4,Q, D4,Q, E4,Q,  D4,DQ, C4,E8, C4,H
        .byte 0,H                // a short rest before it starts again
        .byte $FF
}

.macro tune_bass_data() {
        // root and fifth, two half notes a bar
        .byte C3,H, G3,H,  G2,H, D3,H,  C3,H, G3,H,  G2,H, D3,H
        .byte C3,H, G3,H,  G2,H, D3,H,  C3,H, G3,H,  G2,H, C3,H
        .byte G2,H, D3,H,  G2,H, D3,H,  G2,H, D3,H,  G2,H, G2,H
        .byte C3,H, G3,H,  G2,H, D3,H,  C3,H, G3,H,  G2,H, C3,H
        .byte 0,H
        .byte $FF
}
