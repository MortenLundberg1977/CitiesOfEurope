// ==============================================================
// WORLDCITIES - a "name the capital" game for the Commodore 64
//
// Files on disk (device 8), made by build.bat / tools/build.sh:
//   MAPS     - the region maps (see prepare_data.ps1), loaded to $7400
//   CITIES   - city records, 59 bytes each (see src/cityedit.asm),
//              loaded to $3900 and ended by a 0 byte. The game counts
//              right and wrong answers per city and saves CITIES after
//              each game.
//   TITLESCR, TITLEBMP - the title picture (optional)
//
// Screen: the map of the city's region fills text rows 0-19 in hi-res
// bitmap mode. A raster interrupt switches to text mode for rows 20-24,
// where the question, the three answers and the result are printed. The
// marked city is a flashing sprite ring.
//
// Map projection (the same as tools/render_map.ps1), per region:
//   x = (lon - LON0) / DX, y = (LAT0 - lat) / DY
// in hundredths of a degree; the longitude difference wraps at 360.
//
// Assemble with build.bat (or: java -jar KickAss.jar src/worldcities.asm -odir ../build)
// ==============================================================

.encoding "petscii_upper"

// ---------------- KERNAL ----------------
.label CHROUT = $FFD2
.label GETIN = $FFE4
.label PLOT = $FFF0
.label LOAD = $FFD5
.label SETNAM = $FFBD
.label SETLFS = $FFBA
.label CLOSE = $FFC3
.label CLRCHN = $FFCC
.label SAVE = $FFD8

// ---------------- memory ----------------
.label BITMAP = $2000          // map bitmap (6400 bytes used)
.label SCREEN = $0400          // map colours (rows 0-19) and text (rows 20-24)
.label CITYBUF = $3900         // city data buffer (up to $7316)
.label MAPS = $7400            // region table + packed maps (up to $BFFF; BASIC ROM is off)
.label SPRITE = $0380          // marker sprite (block 14)
.label TITLESCR = $C000        // title colours: screen, colour RAM (+$400), background (+$7E8)
.label TITLEBMP = $E000        // title bitmap, in the RAM under the KERNAL ROM
.const RECLEN = 59             // 58 chars + CR
.const RECMAX = 250            // max records (14750 bytes)
.const REGLEN = 24             // region table entry
.const ROUNDS = 10             // cities per game
.const MAPROWS = 20            // map occupies screen rows 0..19
.const MAPCOLOUR = $D6         // hi-res cell colours: light green land on blue sea
.const SPLITLINE = 206         // raster IRQ line just above the text rows
.const LASTMAPLINE = 210       // last raster line of the map (row 19, pixel line 7)
// record field offsets
.const F_CITY = 0              // 16 chars
.const F_COUNTRY = 17          // 16 chars
.const F_LAT = 34              // 6 chars, e.g. "+55.68"
.const F_LON = 41              // 7 chars, e.g. "-171.77"
.const F_REGION = 49           // 1 char, "1".."9"
.const F_RIGHT = 51            // 3 digits: right answers
.const F_WRONG = 55            // 3 digits: wrong answers
// region table entry (MAPS+1 + index*REGLEN)
.const R_LON0 = 0              // signed word, hundredths of a degree
.const R_LAT0 = 2
.const R_DX = 4                // hundredths of a degree per pixel
.const R_DY = 5
.const R_DATA = 6              // address of the packed map
.const R_NAME = 8              // 16 chars

// ---------------- zero page (math + pointers) ----------------
.label dvd = $FB               // dividend / quotient
.label dvdh = $FC
.label dvs = $FD               // divisor
.label dvsh = $FE
.label reclo = $FB             // record pointer (aliases dvd, used at other times)
.label rechi = $FC

.label ptr = $02               // temp pointer

// ---------------- variables (cassette buffer) ----------------
.label seed = $33C
.label loaded = $33D           // 1 once WORLDMAP and CITIES are in memory
.label numrec = $33E
.label score = $33F
.label round = $340
.label ansidx = $341
.label anspos = $342
.label pxlo = $343             // marker pixel x (0..319)
.label pxhi = $344
.label pypix = $345            // marker pixel y (0..159)
.label latlo = $346
.label lathi = $347
.label lonlo = $348
.label lonhi = $349
.label frames = $34A           // frame counter for the flashing marker
.label negf = $34B
.label numlo = $34C
.label numhi = $34D
.label tmpd = $34E
.label tlo = $34F
.label thi = $350
.label rem = $351
.label remh = $352
.label ma = $353
.label mb = $354
.label res = $355
.label resh = $356
.label opt = $35A              // 3 bytes
.label tmpx = $35D
.label idxtmp = $35E
.label count = $35F
.label tbl = $360              // ROUNDS bytes
.label ctrow = $36A
.label gxcol = $36B
.label titleok = $36C          // 1 when the title picture is in memory
.label ansreg = $36D           // region char of the answer record
.label regptr = $36E           // 2 bytes: region table entry of this round
.label lon0lo = $370
.label lon0hi = $371
.label lat0lo = $372
.label lat0hi = $373
.label regdx = $374
.label regdy = $375
.label candidx = $376
.label saveok = $377
.label sfxtime = $378          // frames left of the current note (0 = silent)
.label sfxpos = $379           // offset of the next note in sfx_tbl
.label sfxwave = $37A          // waveform of the effect
.label upsrc = $FB             // unpack pointers (alias dvd/dvs)
.label updst = $FD

BasicUpstart2(main)

main:
        lda #$36                // BASIC ROM off: RAM at $A000-$BFFF for the maps
        sta $01
        jsr text_mode
        lda #0
        sta $D020               // border black
        sta $D021               // background black
        lda #1
        sta $0286               // white text
        lda #$93                // clear screen
        jsr CHROUT

        lda loaded
        cmp #1
        beq show_start
        // first time: load the title picture and show it while the map
        // and the cities load
        lda #<msg_loading
        sta ptr
        lda #>msg_loading
        sta ptr+1
        jsr print_str
        jsr load_title
        lda titleok
        beq ld_data
        jsr title_on
ld_data:
        jsr load_map
        jsr load_cities
        lda #1
        sta loaded

show_start:
        lda titleok
        beq text_title
        jsr title_on
        jmp wait_start
text_title:
        lda #$93
        jsr CHROUT
        lda #<msg_title
        sta ptr
        lda #>msg_title
        sta ptr+1
        jsr print_str

wait_start:
        jsr GETIN
        cmp #$20
        bne wait_start
        jsr title_off

        lda $DC04               // seed RNG from CIA timer
        sta seed
        lda $DC05
        eor seed
        sta seed
have_data:
        lda numrec
        cmp #10
        bcs enough_cities
        jmp err_few
enough_cities:

        jsr map_mode
        lda #0
        sta score
        sta round
        jsr pick_ten

roundloop:
        jsr hide_marker
        jsr clear_text
        ldx round
        lda tbl,x
        sta ansidx
        jsr get_recptr_ans      // reclo/rechi -> record of ansidx
        ldy #F_REGION
        lda (reclo),y
        sta ansreg
        jsr set_region          // region table entry, corner and scale
        jsr unpack_map          // its map into the bitmap
        jsr get_recptr_ans
        jsr parse_coords
        jsr calc_pixel
        jsr show_marker
        jsr choose_options
        jsr print_question
        jsr get_answer          // A = key "1".."3"
        sec
        sbc #$31               // key "1".."3" -> 0..2
        cmp anspos
        beq was_correct

        // ----- wrong answer -----
        ldx #sfx_wrong-sfx_tbl
        lda #$20                // sawtooth
        jsr play_sfx
        jsr get_recptr_ans
        ldy #F_WRONG+2
        jsr count_up
        jsr clear_text
        ldx #0
        ldy #20
        jsr gotoxy
        lda #<msg_wrong
        sta ptr
        lda #>msg_wrong
        sta ptr+1
        jsr print_str
        jmp show_answer

was_correct:
        inc score
        ldx #sfx_right-sfx_tbl
        lda #$10                // triangle
        jsr play_sfx
        jsr get_recptr_ans
        ldy #F_RIGHT+2
        jsr count_up
        jsr clear_text
        ldx #0
        ldy #20
        jsr gotoxy
        lda #<msg_correct
        sta ptr
        lda #>msg_correct
        sta ptr+1
        jsr print_str

show_answer:
        lda ansidx
        jsr get_recptr
        ldx #2
        ldy #22
        jsr gotoxy
        jsr print_city
        lda #$2C                // ","
        jsr CHROUT
        lda #$20
        jsr CHROUT
        jsr print_country
        ldx #0
        ldy #24
        jsr gotoxy
        lda #<msg_next
        sta ptr
        lda #>msg_next
        sta ptr+1
        jsr print_str

fb_wait:
        jsr GETIN
        cmp #$20
        bne fb_wait

        inc round
        lda round
        cmp #ROUNDS
        beq game_over
        jmp roundloop

game_over:
        jsr hide_marker
        jsr save_cities         // the right/wrong counts
        jsr clear_text
        lda saveok
        bne go_saved
        ldx #0
        ldy #23
        jsr gotoxy
        lda #<msg_noseve
        sta ptr
        lda #>msg_noseve
        sta ptr+1
        jsr print_str
go_saved:
        ldx #0
        ldy #20
        jsr gotoxy
        lda #<msg_over
        sta ptr
        lda #>msg_over
        sta ptr+1
        jsr print_str
        ldx #0
        ldy #22
        jsr gotoxy
        lda #<msg_score
        sta ptr
        lda #>msg_score
        sta ptr+1
        jsr print_str
        lda score
        jsr print_dec8
        lda #$2F                // "/"
        jsr CHROUT
        lda #ROUNDS
        jsr print_dec8
        ldx #0
        ldy #24
        jsr gotoxy
        lda #<msg_again
        sta ptr
        lda #>msg_again
        sta ptr+1
        jsr print_str
over_wait:
        jsr GETIN
        cmp #$20
        bne over_wait
        jmp main

// --------------------------------------------------------------
// err: not enough cities
// --------------------------------------------------------------
err_few:
        lda #0
        sta loaded
        ldx #0
        ldy #24
        jsr gotoxy
        lda #<msg_few
        sta ptr
        lda #>msg_few
        sta ptr+1
        jsr print_str
few_wait:
        jsr GETIN
        cmp #$20
        bne few_wait
        jmp main

// --------------------------------------------------------------
// load MAPS: region table and packed region maps
// --------------------------------------------------------------
load_map:
        lda #fn_save-fn_map
        ldx #<fn_map
        ldy #>fn_map
        jsr SETNAM
        lda #2
        ldx #8
        ldy #0                  // SA=0: load to the X/Y address
        jsr SETLFS
        lda #0
        ldx #<MAPS
        ldy #>MAPS
        jsr LOAD
        bcc lm_ok
        jmp load_err
lm_ok:
        jmp close_ch

// --------------------------------------------------------------
// save CITIES with the new right/wrong counts ("@0:" replaces it).
// Runs on the plain text screen; saveok = 1 if the save worked.
// --------------------------------------------------------------
save_cities:
        jsr text_mode
        lda #$93
        jsr CHROUT
        ldx #0
        ldy #12
        jsr gotoxy
        lda #<msg_saving
        sta ptr
        lda #>msg_saving
        sta ptr+1
        jsr print_str
        lda numrec
        jsr get_recptr          // reclo = just past the last record
        lda #0
        tay
        sta (reclo),y           // end marker
        clc
        lda reclo
        adc #1                  // SAVE end address is one past the last byte
        tax
        lda rechi
        adc #0
        tay
        txa
        pha
        tya
        pha
        lda #fn_end-fn_save
        ldx #<fn_save
        ldy #>fn_save
        jsr SETNAM
        lda #2
        ldx #8
        ldy #1
        jsr SETLFS
        lda #<CITYBUF
        sta ptr
        lda #>CITYBUF
        sta ptr+1
        pla
        tay
        pla
        tax
        lda #ptr                // A = zero-page pointer to the start address
        jsr SAVE
        lda #0
        rol                     // carry set = error
        eor #1
        sta saveok
        jsr close_ch
        jsr read_error          // the drive's status: "00" means it worked
        jmp map_mode

// read the drive's error channel; saveok = 0 unless it starts with "0"
read_error:
        lda #0
        jsr SETNAM
        lda #15
        ldx #8
        ldy #15
        jsr SETLFS
        jsr $FFC0               // OPEN
        bcs re_fail
        ldx #15
        jsr $FFC6               // CHKIN
        bcs re_fail
        jsr $FFCF               // CHRIN: first digit
        cmp #$30
        beq re_more
        lda #0
        sta saveok
re_more:
        jsr $FFCF               // drain the rest of the line
        cmp #$0D
        bne re_more
        jmp re_done
re_fail:
        lda #0
        sta saveok
re_done:
        jsr CLRCHN
        lda #15
        jmp CLOSE

// --------------------------------------------------------------
// count_up: add 1 to the 3-digit counter ending at (reclo),y; stops at 999
// --------------------------------------------------------------
count_up:
        sty idxtmp
        ldx #3
cu_check:
        lda (reclo),y
        cmp #$39                // "9"
        bne cu_add
        dey
        dex
        bne cu_check
        rts                     // 999: leave it
cu_add:
        ldy idxtmp
cu_loop:
        lda (reclo),y
        cmp #$39
        bne cu_inc
        lda #$30                // "9" -> "0", carry to the next digit
        sta (reclo),y
        dey
        jmp cu_loop
cu_inc:
        clc
        adc #1
        sta (reclo),y
        rts

// --------------------------------------------------------------
// set_region: region char (ansreg, "1".."9") -> regptr and its corner and scale
// --------------------------------------------------------------
set_region:
        lda ansreg
        sec
        sbc #$31
        tax
        lda #<MAPS+1
        sta regptr
        lda #>MAPS+1
        sta regptr+1
        cpx #0
        beq sr_got
sr_loop:
        clc
        lda regptr
        adc #REGLEN
        sta regptr
        bcc sr_next
        inc regptr+1
sr_next:
        dex
        bne sr_loop
sr_got:
        lda regptr
        sta ptr
        lda regptr+1
        sta ptr+1
        ldy #R_LON0
        lda (ptr),y
        sta lon0lo
        iny
        lda (ptr),y
        sta lon0hi
        iny
        lda (ptr),y
        sta lat0lo
        iny
        lda (ptr),y
        sta lat0hi
        iny
        lda (ptr),y
        sta regdx
        iny
        lda (ptr),y
        sta regdy
        rts

// --------------------------------------------------------------
// unpack_map: the packed map of regptr into the bitmap.
// $00 and $FF are followed by a run length; other bytes are literal.
// --------------------------------------------------------------
unpack_map:
        lda regptr
        sta ptr
        lda regptr+1
        sta ptr+1
        ldy #R_DATA
        lda (ptr),y
        sta upsrc
        iny
        lda (ptr),y
        sta upsrc+1
        lda #<BITMAP
        sta updst
        lda #>BITMAP
        sta updst+1
um_loop:
        ldy #0
        lda (upsrc),y
        beq um_run
        cmp #$FF
        beq um_run
        sta (updst),y           // literal byte
        jsr um_src1
        jsr um_dst1
        jmp um_end
um_run:
        tax                     // the byte
        iny
        lda (upsrc),y           // run length
        sta count
        jsr um_src1
        jsr um_src1
        txa
        ldy #0
um_fill:
        sta (updst),y
        iny
        cpy count
        bne um_fill
        tya
        clc
        adc updst
        sta updst
        bcc um_end
        inc updst+1
um_end:
        lda updst+1             // done at BITMAP + 6400
        cmp #>(BITMAP+6400)
        bcc um_loop
        lda updst
        cmp #<(BITMAP+6400)
        bcc um_loop
        rts
um_src1:
        inc upsrc
        bne um_s
        inc upsrc+1
um_s:
        rts
um_dst1:
        inc updst
        bne um_d
        inc updst+1
um_d:
        rts

// --------------------------------------------------------------
// load CITIES and count records
// --------------------------------------------------------------
load_cities:
        lda #fn_end-fn_cities
        ldx #<fn_cities
        ldy #>fn_cities
        jsr SETNAM
        lda #2
        ldx #8
        ldy #0                  // SA=0: load to the X/Y address
        jsr SETLFS
        lda #0
        ldx #<CITYBUF
        ldy #>CITYBUF
        jsr LOAD
        bcc lc_ok
        jmp load_err
lc_ok:
        jsr close_ch
        // count records until zero byte or RECMAX
        lda #<CITYBUF
        sta ptr
        lda #>CITYBUF
        sta ptr+1
        ldx #0                  // record count
lc_loop:
        ldy #0
        lda (ptr),y
        beq lc_done
        inx
        clc
        lda ptr
        adc #RECLEN
        sta ptr
        lda ptr+1
        adc #0
        sta ptr+1
        cpx #RECMAX
        beq lc_done
        jmp lc_loop
lc_done:
        stx numrec
        rts

load_err:
        jsr close_ch
        jsr title_off
        lda #0
        sta loaded
        ldx #0
        ldy #24
        jsr gotoxy
        lda #<msg_ferr
        sta ptr
        lda #>msg_ferr
        sta ptr+1
        jsr print_str
le_wait:
        jsr GETIN
        cmp #$20
        bne le_wait
        jmp main

close_ch:
        lda #2
        jsr CLOSE
        jsr CLRCHN
        rts

// --------------------------------------------------------------
// title picture (multicolour bitmap in VIC bank 3)
// --------------------------------------------------------------
// load_title: TITLESCR and TITLEBMP; titleok = 1 if both loaded.
// Without them the game shows the text title instead.
load_title:
        lda #0
        sta titleok
        lda #fn_titlebmp-fn_titlescr
        ldx #<fn_titlescr
        ldy #>fn_titlescr
        jsr SETNAM
        lda #2
        ldx #8
        ldy #0
        jsr SETLFS
        lda #0
        ldx #<TITLESCR
        ldy #>TITLESCR
        jsr LOAD
        php
        jsr close_ch
        plp
        bcs lt_done
        lda #fn_map-fn_titlebmp
        ldx #<fn_titlebmp
        ldy #>fn_titlebmp
        jsr SETNAM
        lda #2
        ldx #8
        ldy #0
        jsr SETLFS
        lda #0
        ldx #<TITLEBMP
        ldy #>TITLEBMP
        jsr LOAD
        php
        jsr close_ch
        plp
        bcs lt_done
        lda #1
        sta titleok
lt_done:
        rts

// title_on: show the picture
title_on:
        ldx #0
to_col:
        lda TITLESCR+$400,x
        sta $D800,x
        lda TITLESCR+$500,x
        sta $D900,x
        lda TITLESCR+$600,x
        sta $DA00,x
        lda TITLESCR+$6E8,x     // last 256 of the 1000 bytes
        sta $DAE8,x
        inx
        bne to_col
        lda #0
        sta $D020
        sta $D015
        lda TITLESCR+$7E8
        sta $D021
        lda $DD00
        and #%11111100          // VIC bank 3: $C000-$FFFF
        sta $DD00
        lda #$08                // screen $C000, bitmap $E000
        sta $D018
        lda #$D8                // multicolour
        sta $D016
        lda #$3B                // bitmap mode
        sta $D011
        rts

// title_off: back to the normal text screen (safe to call any time)
title_off:
        lda $DD00
        ora #%00000011          // VIC bank 0
        sta $DD00
        lda #$C8
        sta $D016
        lda #$1B
        sta $D011
        lda #$15
        sta $D018
        lda #0
        sta $D021
        lda #$93
        jmp CHROUT

// --------------------------------------------------------------
// display modes
// --------------------------------------------------------------
// map_mode: colour the map rows, clear the text rows, start the split
map_mode:
        ldx #0
mm_col:
        lda #MAPCOLOUR
        sta SCREEN,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+MAPROWS*40-$100,x   // last 256 bytes of the 800 map cells
        inx
        bne mm_col
        ldx #0
mm_blue:
        lda #6                  // blue: see irq_text
        sta $D800,x
        sta $D900,x
        sta $DA00,x
        sta $D800+MAPROWS*40-$100,x
        inx
        bne mm_blue
        ldx #0
mm_txt:
        lda #$20
        sta SCREEN+MAPROWS*40,x
        lda #1
        sta $D800+MAPROWS*40,x
        inx
        cpx #(25-MAPROWS)*40
        bne mm_txt

        ldx #62                 // marker sprite shape
mm_spr:
        lda marker_shape,x
        sta SPRITE,x
        dex
        bpl mm_spr
        lda #SPRITE/64
        sta SCREEN+$3F8
        lda #0
        sta $D015               // marker hidden until a round starts
        sta $D017
        sta $D01D
        sta $D01C

        sei
        lda #$7F
        sta $DC0D               // no CIA timer interrupts: the raster IRQ
        lda $DC0D               // runs the KERNAL keyboard scan instead
        lda #<irq_map
        sta $0314
        lda #>irq_map
        sta $0315
        lda #0
        sta $D012
        lda #$1B                // raster compare bit 8 = 0
        sta $D011
        lda #1
        sta $D01A               // raster interrupt on
        sta $D019
        cli
        rts

// text_mode: normal KERNAL text screen and interrupts
text_mode:
        sei
        lda #0
        sta $D01A
        lda #1
        sta $D019
        lda #$31
        sta $0314
        lda #$EA
        sta $0315
        lda #$81
        sta $DC0D               // CIA timer interrupt back on
        lda #$1B
        sta $D011
        lda #$15
        sta $D018
        lda #0
        sta $D015
        sta $D404               // stop a sound that is still playing
        sta sfxtime
        cli
        rts

// --------------------------------------------------------------
// sound effects on SID voice 1, played by the raster interrupt.
// play_sfx: X = offset of the effect in sfx_tbl, A = waveform.
// An effect is a list of notes: frequency (word), frames; 0 frames ends it.
// --------------------------------------------------------------
play_sfx:
        sei
        stx sfxpos
        sta sfxwave
        lda #0
        sta $D404               // gate off, so the new sound starts cleanly
        lda #$0F
        sta $D418               // volume
        lda #$00
        sta $D405               // attack 0, decay 0
        lda #$F9
        sta $D406               // sustain 15, release 9
        lda #1
        sta sfxtime
        jsr sfx_tick            // first note
        lda sfxwave
        ora #1                  // gate on
        sta $D404
        cli
        rts

// once a frame: next note when the current one is over
sfx_tick:
        lda sfxtime
        beq st_done             // nothing playing
        dec sfxtime
        bne st_done
        ldx sfxpos
        lda sfx_tbl+2,x
        beq st_end
        sta sfxtime
        lda sfx_tbl,x
        sta $D400
        lda sfx_tbl+1,x
        sta $D401
        inx
        inx
        inx
        stx sfxpos
st_done:
        rts
st_end:
        lda sfxwave             // gate off: the note fades out
        sta $D404
        rts

// SID frequencies for PAL: Hz * 17.03
sfx_tbl:
sfx_right:                      // C5 E5 G5 C6, quick and rising
        .word $22CF
        .byte 4
        .word $2BDC
        .byte 4
        .word $3428
        .byte 4
        .word $459D
        .byte 12
        .word 0
        .byte 0
sfx_wrong:                      // A3 then E3, low and falling
        .word $0EA3
        .byte 8
        .word $0AF7
        .byte 18
        .word 0
        .byte 0

// top of the screen: bitmap on, flash the marker, scan the keyboard
irq_map:
        lda #1
        sta $D019
        lda #$3B                // bitmap mode
        sta $D011
        lda #$18                // screen $0400, bitmap $2000
        sta $D018
        jsr sfx_tick
        inc frames
        lda frames
        and #$08
        beq im_red
        lda #1                  // white
        .byte $2C               // skip the next 2-byte instruction
im_red:
        lda #2                  // red
        sta $D027
        lda #<irq_text
        sta $0314
        lda #>irq_text
        sta $0315
        lda #SPLITLINE
        sta $D012
        jmp $EA31               // KERNAL: keyboard, clock, then return

// row 20: text mode for the question
irq_text:
        lda #1
        sta $D019
        // Switch during the map's last line: switching later would miss the
        // bad line of row 20. The rest of that line shows text-mode row 19
        // (reverse characters, colour RAM blue), which looks like sea.
it_wait:
        lda $D012
        cmp #LASTMAPLINE
        bcc it_wait
        lda #$1B                // text mode
        sta $D011
        lda #$15                // screen $0400, ROM characters
        sta $D018
        lda #<irq_map
        sta $0314
        lda #>irq_map
        sta $0315
        lda #0
        sta $D012
        jmp $EA81               // KERNAL: restore registers, return

// --------------------------------------------------------------
// choose ROUNDS distinct random record indices
// --------------------------------------------------------------
pick_ten:
        lda #0
        sta tmpx              // slot counter (rndn clobbers X)
pt_loop:
        lda numrec
        jsr rndn
        ldy #0
pt_chk:
        cpy tmpx
        beq pt_ok
        cmp tbl,y
        beq pt_retry
        iny
        jmp pt_chk
pt_ok:
        ldy tmpx
        sta tbl,y
        inc tmpx
        lda tmpx
        cmp #ROUNDS
        beq pt_done
        jmp pt_loop
pt_retry:
        jmp pt_loop
pt_done:
        rts

// --------------------------------------------------------------
// options: correct city + 2 random distractors, answer shuffled
// --------------------------------------------------------------
choose_options:
        lda #3
        jsr rndn
        sta anspos              // 0..2
        ldx #0
co_loop:
        cpx anspos
        bne co_other
        lda ansidx
        sta opt,x
        jmp co_next
co_other:
        stx tmpx
co_retry:
        lda numrec
        jsr rndn
        cmp ansidx
        beq co_retry
        sta candidx             // only cities from the same region
        jsr get_recptr
        ldy #F_REGION
        lda (reclo),y
        cmp ansreg
        bne co_retry
        lda candidx
        ldy #0
co_chk:
        cpy tmpx
        beq co_ok
        cmp opt,y
        beq co_retry
        iny
        jmp co_chk
co_ok:
        ldx tmpx
        sta opt,x
co_next:
        inx
        cpx #3
        bne co_loop
        rts

// --------------------------------------------------------------
// record pointer for the answer (reclo/rechi)
// --------------------------------------------------------------
get_recptr_ans:
        lda ansidx
        // fall through

// --------------------------------------------------------------
// get_recptr: A = record index -> reclo/rechi = CITYBUF + A*RECLEN
// --------------------------------------------------------------
get_recptr:
        sta idxtmp
        lda #<CITYBUF
        sta reclo
        lda #>CITYBUF
        sta rechi
        ldx idxtmp
        beq grp_done
grp_loop:
        clc
        lda reclo
        adc #RECLEN
        sta reclo
        lda rechi
        adc #0
        sta rechi
        dex
        bne grp_loop
grp_done:
        rts

// --------------------------------------------------------------
// parse latitude/longitude of record at reclo/rechi
// --------------------------------------------------------------
parse_coords:
        lda reclo
        clc
        adc #F_LAT
        sta ptr
        lda rechi
        adc #0
        sta ptr+1
        jsr parse_num
        lda numlo
        sta latlo
        lda numhi
        sta lathi
        lda reclo
        clc
        adc #F_LON
        sta ptr
        lda rechi
        adc #0
        sta ptr+1
        jsr parse_num
        lda numlo
        sta lonlo
        lda numhi
        sta lonhi
        rts

// --------------------------------------------------------------
// parse a signed decimal number at ptr, e.g. "-55.68"
// result (centi-degrees, signed) in numlo/numhi
// --------------------------------------------------------------
parse_num:
        ldy #0
        lda #0
        sta negf
        sta numlo
        sta numhi
pn_sp:
        lda (ptr),y
        cmp #$20                // skip padding spaces
        bne pn_sign
        iny
        jmp pn_sp
pn_sign:
        cmp #$2D                // "-"
        bne pn_plus
        lda #1
        sta negf
        iny
        jmp pn_int
pn_plus:
        cmp #$2B                // "+"
        bne pn_int
        iny
pn_int:
        lda (ptr),y
        sec
        sbc #$30
        cmp #10
        bcs pn_dot
        sta tmpd
        lda numlo               // num = num*10 + digit
        asl
        asl
        adc numlo               // num*5 (degrees fit in a byte)
        asl                     // num*10
        adc tmpd
        sta numlo
        iny
        jmp pn_int
pn_dot:
        lda (ptr),y
        cmp #$2E                // "."
        bne pn_mult
        iny
        lda #0
        sta tmpd
        // first decimal digit
        lda (ptr),y
        sec
        sbc #$30
        cmp #10
        bcs pn_mult
        sta tmpd
        asl
        asl
        adc tmpd                // d*5
        asl                     // d*10
        sta tmpd
        iny
        // second decimal digit
        lda (ptr),y
        sec
        sbc #$30
        cmp #10
        bcs pn_mult
        clc
        adc tmpd
        sta tmpd
        iny
pn_mult:
        lda numlo
        sta ma
        lda #100
        sta mb
        jsr mul8                // res = degrees * 100
        clc
        lda res
        adc tmpd
        sta numlo
        lda resh
        adc #0
        sta numhi
        lda negf
        beq pn_done
        sec
        lda #0
        sbc numlo
        sta numlo
        lda #0
        sbc numhi
        sta numhi
pn_done:
        rts

// --------------------------------------------------------------
// lat/lon (hundredths of a degree) -> marker pixel on the region map
//   px = (lon - LON0) / DX   (the difference wraps at 36000, so a region
//                             may cross the 180 degree line), 0..319
//   py = (LAT0 - lat) / DY   0..159
// tools/render_map.ps1 draws the maps with the same numbers.
// --------------------------------------------------------------
calc_pixel:
        sec
        lda lonlo
        sbc lon0lo
        sta dvd
        lda lonhi
        sbc lon0hi
        sta dvdh
        bpl cp_xdiv             // west of LON0: add 360 degrees
        clc
        lda dvd
        adc #<36000
        sta dvd
        lda dvdh
        adc #>36000
        sta dvdh
cp_xdiv:
        lda regdx
        sta dvs
        lda #0
        sta dvsh
        jsr div16
        lda dvd
        sta pxlo
        lda dvdh
        sta pxhi
        cmp #>320               // keep it on the map: at most 319
        bcc cp_y
        bne cp_xmax
        lda pxlo
        cmp #<320
        bcc cp_y
cp_xmax:
        lda #<319
        sta pxlo
        lda #>319
        sta pxhi
cp_y:
        sec
        lda lat0lo
        sbc latlo
        sta dvd
        lda lat0hi
        sbc lathi
        sta dvdh
        bpl cp_div              // north of the map -> top row
        lda #0
        sta pypix
        rts
cp_div:
        lda regdy
        sta dvs
        lda #0
        sta dvsh
        jsr div16
        lda dvdh
        bne cp_low
        lda dvd
        cmp #MAPROWS*8
        bcc cp_store
cp_low:
        lda #MAPROWS*8-1        // south of the map -> bottom row
cp_store:
        sta pypix
        rts

// --------------------------------------------------------------
// marker sprite (centre at 5,5 of the sprite)
// --------------------------------------------------------------
show_marker:
        clc
        lda pxlo
        adc #24-5               // screen left edge is sprite x 24
        sta $D000
        lda pxhi
        adc #0
        and #1
        sta $D010
        clc
        lda pypix
        adc #50-5               // screen top is sprite y 50
        sta $D001
        lda #1
        sta $D015
        rts

hide_marker:
        lda #0
        sta $D015
        rts

// --------------------------------------------------------------
// question + 3 options on rows 20..23
// --------------------------------------------------------------
print_question:
        ldx #0
        ldy #20
        jsr gotoxy
        lda regptr              // region name, trailing spaces trimmed
        sta ptr
        lda regptr+1
        sta ptr+1
        ldy #R_NAME+15
pq_trim:
        lda (ptr),y
        cmp #$20
        bne pq_end
        dey
        cpy #R_NAME
        bcs pq_trim
pq_end:
        iny
        sty count
        ldy #R_NAME
pq_name:
        cpy count
        bcs pq_named
        lda (ptr),y
        jsr CHROUT
        iny
        jmp pq_name
pq_named:
        lda #<msg_q
        sta ptr
        lda #>msg_q
        sta ptr+1
        jsr print_str

        lda #0
        sta tmpx
pq_loop:
        ldx tmpx
        lda opt,x
        jsr get_recptr
        lda tmpx
        clc
        adc #21
        tay
        ldx #2
        jsr gotoxy
        lda tmpx
        clc
        adc #$31                // "1".."3"
        jsr CHROUT
        lda #$2E                // "."
        jsr CHROUT
        lda #$20
        jsr CHROUT
        jsr print_city
        inc tmpx
        lda tmpx
        cmp #3
        bne pq_loop
        rts

get_answer:
        jsr GETIN
        cmp #$31
        bcc ga
        cmp #$34
        bcs ga
        rts
ga:
        jmp get_answer

// --------------------------------------------------------------
// print city / country of record at reclo/rechi,
// trailing spaces trimmed
// --------------------------------------------------------------
print_city:
        ldy #F_CITY+15
pc_trim:
        lda (reclo),y
        cmp #$20
        bne pc_end
        dey
        bpl pc_trim
pc_end:
        iny
        sty count
        ldy #F_CITY
        jmp print_field

print_country:
        ldy #F_COUNTRY+15
pco_trim:
        lda (reclo),y
        cmp #$20
        bne pco_end
        dey
        cpy #F_COUNTRY
        bcs pco_trim
pco_end:
        iny
        sty count
        ldy #F_COUNTRY
        // fall through

// print (reclo),y up to (not including) offset count
print_field:
        cpy count
        bcs pf_done
        lda (reclo),y
        jsr CHROUT
        iny
        jmp print_field
pf_done:
        rts

// --------------------------------------------------------------
// clear text rows 20..24
// --------------------------------------------------------------
clear_text:
        ldx #0
        lda #$20
ct_loop:
        sta SCREEN+MAPROWS*40,x
        inx
        cpx #(25-MAPROWS)*40
        bne ct_loop
        rts

// --------------------------------------------------------------
// print zero-terminated string at ptr
// --------------------------------------------------------------
print_str:
        ldy #0
ps_loop:
        lda (ptr),y
        beq ps_done
        jsr CHROUT
        iny
        bne ps_loop
ps_done:
        rts

// --------------------------------------------------------------
// gotoxy: X = column, Y = row
// --------------------------------------------------------------
gotoxy:                         // KERNAL PLOT wants X = row, Y = column
        stx gxcol
        tya
        tax
        ldy gxcol
        clc
        jsr PLOT
        rts

// --------------------------------------------------------------
// print A (0..255) as decimal
// --------------------------------------------------------------
print_dec8:
        ldx #$30
        cmp #100
        bcc pd_tens
        ldx #$30
pd_h:
        cmp #100
        bcc pd_hout
        sbc #100
        inx
        jmp pd_h
pd_hout:
        pha
        txa
        jsr CHROUT
        pla
        ldx #$30
pd_t:
        cmp #10
        bcc pd_tout
        sbc #10
        inx
        jmp pd_t
pd_tout:
        pha
        txa
        jsr CHROUT
        pla
        jmp pd_one
pd_tens:
        cmp #10
        bcc pd_ones
        sbc #10
        inx
        jmp pd_tens
pd_ones:
        cpx #$30
        beq pd_one
        pha
        txa
        jsr CHROUT
        pla
pd_one:
        clc
        adc #$30
        jsr CHROUT
        rts

// --------------------------------------------------------------
// RNG: semi-random byte from CIA timers
// --------------------------------------------------------------
rnd:
        lda $DC04
        eor seed
        clc
        adc $DC05
        sta seed
        rts

// rndn: A = N -> A in 0..N-1   ((rnd * N) >> 8)
rndn:
        sta mb
        jsr rnd
        sta ma
        jsr mul8
        lda resh
        rts

// --------------------------------------------------------------
// mul8: ma * mb -> res/resh (unsigned 8x8 -> 16)
// --------------------------------------------------------------
mul8:
        lda #0
        sta res
        sta resh
        ldx #8
m_loop:
        asl ma                  // C = current bit of ma
        php
        asl res
        rol resh
        plp
        bcc m_next
        lda res
        clc
        adc mb
        sta res
        lda resh
        adc #0
        sta resh
m_next:
        dex
        bne m_loop
        rts

// --------------------------------------------------------------
// div16: dvd/dvdh / dvs/dvsh -> quotient in dvd/dvdh, rem in rem
// --------------------------------------------------------------
div16:
        lda #0
        sta rem
        sta remh
        ldx #16
d_loop:
        asl dvd
        rol dvdh
        rol rem
        rol remh
        lda rem
        sec
        sbc dvs
        tay
        lda remh
        sbc dvsh
        bcc d_skip
        sty rem
        sta remh
        inc dvd
d_skip:
        dex
        bne d_loop
        rts

// --------------------------------------------------------------
// marker sprite: an 11x11 ring with a centre dot
// --------------------------------------------------------------
marker_shape:
        .byte $3E,$00,$00
        .byte $63,$00,$00
        .byte $C1,$80,$00
        .byte $80,$80,$00
        .byte $80,$80,$00
        .byte $88,$80,$00
        .byte $80,$80,$00
        .byte $80,$80,$00
        .byte $C1,$80,$00
        .byte $63,$00,$00
        .byte $3E,$00,$00
        .fill 30, 0

// --------------------------------------------------------------
// strings and filenames
// --------------------------------------------------------------
msg_title:
        .text "**** WORLDCITIES ****"
        .byte $0D, $0D
        .text "10 CAPITALS WILL BE MARKED ON THE MAP."
        .byte $0D
        .text "PICK THE RIGHT CITY FROM THREE"
        .byte $0D
        .text "CHOICES USING KEYS 1-3."
        .byte $0D, $0D
        .text "PRESS SPACE TO START"
        .byte $0D, $0D, 0
msg_loading:
        .text "LOADING MAP AND CITIES..."
        .byte 0
msg_q:
        .text ": WHICH CITY IS MARKED?"
        .byte 0
msg_correct:
        .text "CORRECT! IT IS:"
        .byte 0
msg_wrong:
        .text "NO, IT IS:"
        .byte 0
msg_next:
        .text "PRESS SPACE"
        .byte 0
msg_over:
        .text "GAME OVER"
        .byte 0
msg_score:
        .text "YOUR SCORE: "
        .byte 0
msg_again:
        .text "PRESS SPACE TO PLAY AGAIN"
        .byte 0
msg_ferr:
        .text "FILE ERROR - CHECK DISK. SPACE=RETRY"
        .byte 0
msg_few:
        .text "NEED AT LEAST 10 CITIES. SPACE=RETRY"
        .byte 0
msg_saving:
        .text "SAVING SCORES..."
        .byte 0
msg_noseve:
        .text "COULD NOT SAVE THE SCORES TO DISK"
        .byte 0

fn_titlescr:
        .text "TITLESCR"
fn_titlebmp:
        .text "TITLEBMP"
fn_map:
        .text "MAPS"
fn_save:
        .text "@0:"
fn_cities:
        .text "CITIES"
fn_end:
