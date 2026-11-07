// ==============================================================
// The game, shared by World Cities and Cities of Europe: this file is the
// same in both projects. src/config.asm has what differs (title text, hint,
// title tune) and is imported first by the main source file.
//
// Files on disk (device 8), made by build.bat / tools/build.sh:
//   TITLE     - the title picture, RLE-packed, loaded to $6C40 and unpacked to
//               $C000 (colours) and $E000 (bitmap)
//   HIGHCODE  - the second part of this program, loaded to $C800
//   HISCORES  - the top-10 table, loaded to $AB00, saved after a new entry
//   MAPS      - region table and RLE-packed region maps, loaded to $6C40
//   FLAGS     - flag sprites (Cities of Europe), loaded to $B000
//   LANDMARKS - landmark sprites, loaded to $AC00
//   CITIES    - city records, 59 bytes each (see src/cityedit.asm),
//               loaded to $3900 and ended by a 0 byte. The game counts
//               right and wrong answers per city and saves CITIES after
//               each game.
//
// Screen: the map of the city's region fills text rows 0-19 in hi-res
// bitmap mode. A raster interrupt switches to text mode for rows 20-24,
// where the question, the three answers and the result are printed. The
// marked city is a flashing sprite ring (sprite 0); the flag is sprite 1,
// a landmark picture sprite 2.
//
// Map projection (the same as tools/render_map.ps1), per region:
//   x = (lon - LON0) / DX, y = (LAT0 - lat) / DY
// in hundredths of a degree; the longitude difference wraps at 360.
//
// Points for a right answer: 3 without a hint, 2 after the first hint,
// 1 after the 50/50; plus 2 if answered within 5 seconds, 1 within 10.
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
.label OPEN = $FFC0
.label CHKIN = $FFC6
.label CHRIN = $FFCF
.label CHKOUT = $FFC9

// ---------------- memory ----------------
.label LANDSPR = $0200         // landmark sprite (block 8: the BASIC input buffer)
.label FLAGSPR = $02C0         // flag sprite (block 11, free RAM)
.label SPRITE = $0380          // marker sprite (block 14)
.label CROSSSPR = $03C0        // map game cross-hair sprite (block 15)
.label SCREEN = $0400          // map colours (rows 0-19) and text (rows 20-24)
.label BITMAP = $2000          // map bitmap (6400 bytes used)
.label CITYBUF = $3900         // city data buffer (up to $6C2C)
.label MAPS = $6C40            // region table + packed maps (up to $AAFF)
.label TITLEPACK = $6C40       // the packed title, before the maps load over it
.label CITYLOAD = $6C40        // CITIES loads here too, and is unpacked to CITYBUF
.label SCORESBUF = $2000       // SCORES loads into the (not yet used) bitmap
.label HISCORES = $AB00        // 10 entries: name (10), points, spare (BASIC ROM is off)
.label VARS2 = $AB80           // more variables
.label LANDMARKS = $AC00       // landmark table
.label FLAGS = $B000           // flag table
.label TITLESCR = $C000        // title colours: screen, colour RAM (+$400), background (+$7E8)
.label HIGHCODE = $C800        // second part of the program
.label TITLEBMP = $E000        // title bitmap, in the RAM under the KERNAL ROM
.const FLAGLEN = 84            // flag / landmark table entry
.const RECLEN = 59             // 58 chars + CR
.const RECMAX = 220            // max records (12980 bytes)
.const REGLEN = 24             // region table entry
.const ROUNDS = 10             // cities per game
.const MAPROWS = 20            // map occupies screen rows 0..19
.const MAPCOLOUR = $D6         // hi-res cell colours: light green land on blue sea
.const SPLITLINE = 206         // raster IRQ line just above the text rows
.const LASTMAPLINE = 210       // last raster line of the map (row 19, pixel line 7)
.const HSLEN = 12              // high-score entry
.const HSNAME = 10             // name length
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
.const TIME_COL = FLAG_HINT == 1 ? 23 : 31   // row 24: hint text left of it
// file numbers (see file_len etc.)
.const F_TITLE = 0
.const F_HIGHCODE = 1
.const F_HISCORES = 2
.const F_MAPS = 3
.const F_FLAGS = 4
.const F_LANDMARKS = 5
.const F_CITIES = 6
.const F_SCORES = 7
.const F_SAVEHISCORES = 8
.const F_SAVESCORES = 9

// ---------------- zero page ----------------
.label ptr = $02               // temp pointer
.label ptr2 = $04              // second pointer ($04-$09 belong to BASIC, which is off)
.label mptr = $06              // music interrupt only
.label mptr2 = $08
.label dvd = $FB               // dividend / quotient
.label dvdh = $FC
.label dvs = $FD               // divisor
.label dvsh = $FE
.label reclo = $FB             // record pointer (aliases dvd, used at other times)
.label rechi = $FC
.label upsrc = $FB             // unpack pointers (alias dvd/dvs)
.label updst = $FD

// ---------------- variables (cassette buffer) ----------------
.label seed = $33C
.label loaded = $33D           // 1 once everything is in memory
.label numrec = $33E
.label score = $33F            // points this game
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
// more variables at $AB80
.label rights = VARS2+0        // right answers this game
.label hintlvl = VARS2+1       // hints used this round (0-2)
.label secs = VARS2+2          // seconds since the question appeared (stops at 99)
.label subsec = VARS2+3        // frames 0-49
.label lastsecs = VARS2+4      // seconds shown on screen
.label removed = VARS2+6       // option removed by the 50/50 ($FF: none)
.label gained = VARS2+8        // points of this answer
.label upendlo = VARS2+9       // unpack end address
.label upendhi = VARS2+10
.label fnlen = VARS2+11        // load_file / save_file arguments
.label fnlo = VARS2+12
.label fnhi = VARS2+13
.label addrlo = VARS2+14
.label addrhi = VARS2+15
.label best = VARS2+16         // pick_ten: best candidate
.label bestlo = VARS2+17       // and its key
.label besthi = VARS2+18
.label tries = VARS2+19
.label keylo = VARS2+20
.label keyhi = VARS2+21
.label n16lo = VARS2+22        // read3 / print_dec16
.label n16hi = VARS2+23
.label hspos = VARS2+24        // new high-score entry 0-9 ($FF: none)
.label namelen = VARS2+25
.label mus1pos = VARS2+26      // music: offsets in the two tunes (2 bytes each)
.label mus2pos = VARS2+28
.label mus1time = VARS2+30
.label mus2time = VARS2+31
.label musicon = VARS2+32
.label waitlo = VARS2+33       // attract mode timer
.label waithi = VARS2+34
.label tmp16lo = VARS2+35
.label tmp16hi = VARS2+36
.label pass = VARS2+37
.label lastkey = VARS2+38
.label totrlo = VARS2+39       // stats: totals
.label totrhi = VARS2+40
.label totwlo = VARS2+41
.label totwhi = VARS2+42
.label NAMEIN = VARS2+48       // 10 bytes: the name being typed
.label NAMEBUF = VARS2+64      // 16 bytes: name being looked up
.label tbl = VARS2+80          // 20 bytes: the cities of the game
.label mode = VARS2+100        // 0: name the marked city, 1: find it on the map
.label players = VARS2+101     // 1 or 2
.label curplayer = VARS2+102   // 0 or 1
.label pscore = VARS2+103      // 2 bytes: points of each player
.label prights = VARS2+105     // 2 bytes: right answers of each player
.label nrounds = VARS2+107     // 10 or 20
.label crossxlo = VARS2+108    // cross-hair pixel on the map
.label crossxhi = VARS2+109
.label crossy = VARS2+110
.label holdcnt = VARS2+111     // frames a direction key has been held
.label lastframe = VARS2+112
.label m16lo = VARS2+113       // mul16x8: 16-bit factor
.label m16hi = VARS2+114
.label r24 = VARS2+115         // 3 bytes: mul16x8 result
.label distlo = VARS2+118      // map game: distance
.label disthi = VARS2+119
.label alo = VARS2+120
.label ahi = VARS2+121
.label blo = VARS2+122
.label bhi = VARS2+123

// say: print a text at a column and row
.macro say(col, row, str) {
        ldx #col
        ldy #row
        jsr gotoxy
        jsr print_inline
        .text str
        .byte 0
}

BasicUpstart2(main)

main:
        lda #$36                // BASIC ROM off: RAM at $A000-$BFFF
        sta $01
        cld
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
        // first time: the title picture first, then music while the rest loads
        lda #1
        sta players
        lda #0
        sta mode
        say(0, 0, "LOADING...")
        jsr load_title
        lda titleok
        beq ld_data
        jsr title_on
ld_data:
        ldx #F_HIGHCODE
        jsr load_named
        jsr music_on
        jsr load_cities         // CITIES and SCORES (before MAPS: it unpacks from there)
        ldx #F_HISCORES
        jsr load_named
        ldx #F_MAPS
        jsr load_named
.if (FLAG_HINT == 1) {
        ldx #F_FLAGS
        jsr load_named
}
        ldx #F_LANDMARKS
        jsr load_named
        lda #1
        sta loaded

show_start:
        jsr title_loop          // title, high scores, stats; returns on Space
        jsr title_off

        lda $DC04               // seed RNG from CIA timer
        sta seed
        lda $DC05
        eor seed
        sta seed
        lda numrec
        cmp #10
        bcs enough_cities
        jmp err_few
enough_cities:
        jsr game_menu           // mode and number of players

        jsr map_mode
        lda #0
        sta round
        sta pscore
        sta pscore+1
        sta prights
        sta prights+1
        lda #ROUNDS             // 10 rounds a player, taking turns
        ldx players
        cpx #2
        bne gs_one
        asl
gs_one:
        sta nrounds
        jsr pick_ten

roundloop:
        lda players             // whose turn: the border shows it
        cmp #2
        bne rl_one
        lda round
        and #1
        tax
        stx curplayer
        lda player_colour,x
        sta $D020
        jmp rl_go
rl_one:
        lda #0
        sta curplayer
rl_go:
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
        lda mode
        beq name_round
        jsr find_on_map         // the other mode: point at the map
        jmp show_answer

name_round:
        jsr show_marker
        jsr choose_options
        jsr print_question
        jsr get_answer          // A = option 0..2
        cmp anspos
        beq was_correct

        // ----- wrong answer -----
        lda #0
        sta gained
        jsr answer_wrong
        say(0, 20, "NO, IT IS:")
        jmp show_answer

was_correct:
        // points: 3, 2 or 1 by hints, plus 2 or 1 for speed
        lda #3
        sec
        sbc hintlvl
        sta gained
        lda secs
        cmp #10
        bcs wc_slow
        inc gained
        cmp #5
        bcs wc_slow
        inc gained
wc_slow:
        jsr answer_right
        say(0, 20, "CORRECT! +")
        jsr print_gained
        jsr print_inline
        .text ". IT IS:"
        .byte 0

show_answer:
.if (FLAG_HINT == 1) {
        jsr show_flag           // the flag, if no hint showed it
}
        jsr show_landmark
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
        say(0, 24, "PRESS SPACE")
        lda players             // two players: say whose turn is next
        cmp #2
        bne sa_wait
        ldx round
        inx
        cpx nrounds
        beq sa_wait
        jsr print_inline
        .text ": PLAYER "
        .byte 0
        lda curplayer
        eor #1
        clc
        adc #$31
        jsr CHROUT
sa_wait:
        jsr wait_continue

        inc round
        lda round
        cmp nrounds
        beq game_over
        jmp roundloop

game_over:
        jsr hide_marker
        jsr save_scores         // the right/wrong counts
        lda #0
        sta $D020
        jsr clear_text
        lda saveok
        bne go_saved
        say(0, 23, "COULD NOT SAVE TO DISK")
go_saved:
        say(0, 20, "GAME OVER")
        lda players
        cmp #2
        beq go_two
        lda pscore
        sta score
        jsr check_hiscore
        say(0, 21, "YOU SCORED ")
        ldx #0
        jsr print_result
        lda hspos
        bpl go_newhs
        jmp go_wait
go_newhs:
        say(0, 22, "A NEW HIGH SCORE!")
        jmp go_wait
go_two:
        say(0, 21, "PLAYER 1: ")
        ldx #0
        jsr print_result
        say(0, 22, "PLAYER 2: ")
        ldx #1
        jsr print_result
        ldx #0
        ldy #23
        jsr gotoxy
        lda pscore
        cmp pscore+1
        beq go_draw
        lda #$31                // "1"
        bcs go_win
        lda #$32
go_win:
        pha
        jsr print_inline
        .text "PLAYER "
        .byte 0
        pla
        jsr CHROUT
        jsr print_inline
        .text " WINS!"
        .byte 0
        jmp go_wait
go_draw:
        jsr print_inline
        .text "A DRAW!"
        .byte 0
go_wait:
        say(0, 24, "PRESS SPACE")
        jsr wait_continue
        // a high-score entry for each player who made the table
        lda #0
        sta curplayer
go_hs:
        ldx curplayer
        lda pscore,x
        sta score
        jsr check_hiscore
        lda hspos
        bmi go_next
        jsr enter_hiscore       // name, table, save
go_next:
        inc curplayer
        lda curplayer
        cmp players
        bne go_hs
        jmp main

// print_result: player X's points and right answers: "34 POINTS, 8 RIGHT"
print_result:
        stx tmpx
        lda pscore,x
        jsr print_dec8
        jsr print_inline
        .text " POINTS, "
        .byte 0
        ldx tmpx
        lda prights,x
        jsr print_dec8
        jsr print_inline
        .text " RIGHT"
        .byte 0
        rts

// print_gained: "3 POINTS" or "1 POINT"
print_gained:
        lda gained
        jsr print_dec8
        jsr print_inline
        .text " POINT"
        .byte 0
        lda gained
        cmp #1
        beq pg_one
        lda #$53                // "S"
        jsr CHROUT
pg_one:
        rts

// answer_right / answer_wrong: sound, count, points (gained) for the player
answer_right:
        ldx curplayer
        inc prights,x
        lda pscore,x
        clc
        adc gained
        sta pscore,x
        ldx #sfx_right-sfx_tbl
        lda #$10                // triangle
        jsr play_sfx
        jsr get_recptr_ans
        ldy #F_RIGHT+2
        jsr count_up
        jmp clear_text
answer_wrong:
        ldx curplayer
        lda pscore,x
        clc
        adc gained              // the map game gives points for near misses too
        sta pscore,x
        ldx #sfx_wrong-sfx_tbl
        lda #$20                // sawtooth
        jsr play_sfx
        jsr get_recptr_ans
        ldy #F_WRONG+2
        jsr count_up
        jmp clear_text

player_colour:
        .byte 14, 8             // border: light blue for player 1, orange for player 2

// --------------------------------------------------------------
// game_menu: which game, and how many players
// --------------------------------------------------------------
game_menu:
        lda #$93
        jsr CHROUT
        say(12, 3, "CHOOSE A GAME")
        say(5, 7, "1  NAME THE MARKED CITY")
        say(6, 8, "(PICK FROM THREE, H FOR HINTS)")
        say(5, 11, "2  FIND THE CITY ON THE MAP")
        say(6, 12, "(POINT AT IT: CLOSER SCORES MORE)")
        say(5, 16, "P  PLAYERS: ")
        lda players
        clc
        adc #$30
        jsr CHROUT
        lda players
        cmp #2
        bne gm_key
        say(6, 17, "(TAKING TURNS, 10 CITIES EACH)")
gm_key:
        jsr poll_input
        cmp #$31                // "1"
        beq gm_one
        cmp #$32                // "2"
        beq gm_two
        cmp #$50                // "P"
        bne gm_key
        lda players
        eor #3                  // 1 <-> 2
        sta players
        jmp game_menu
gm_one:
        lda #0
        sta mode
        rts
gm_two:
        lda #1
        sta mode
        rts

// --------------------------------------------------------------
// err: not enough cities
// --------------------------------------------------------------
err_few:
        lda #0
        sta loaded
        say(0, 24, "NEED AT LEAST 10 CITIES. SPACE=RETRY")
        jsr wait_continue
        jmp main

// print_inline: print the zero-terminated text that follows the JSR
print_inline:
        pla
        sta ptr
        pla
        sta ptr+1
pi_next:
        inc ptr
        bne pi_ch
        inc ptr+1
pi_ch:
        ldy #0
        lda (ptr),y
        beq pi_end
        jsr CHROUT
        jmp pi_next
pi_end:
        lda ptr+1               // return to the byte after the 0
        pha
        lda ptr
        pha
        rts

// --------------------------------------------------------------
// input: the keyboard. poll_input: A = a key, or 0 if none
// --------------------------------------------------------------
poll_input:
        jmp GETIN

// wait_continue: until Space or Return
wait_continue:
        jsr poll_input
        cmp #$20
        beq wc_done
        cmp #$0D
        bne wait_continue
wc_done:
        rts

// --------------------------------------------------------------
// get_answer: keys 1-3; H for a hint. Shows the seconds. Returns A = option 0..2.
// --------------------------------------------------------------
get_answer:
        lda #0
        sta hintlvl
        lda #$FF
        sta removed
        sta lastsecs
        sei
        lda #0
        sta secs
        sta subsec
        cli
        jsr show_hintline
ga_loop:
        lda secs
        cmp lastsecs
        beq ga_input
        sta lastsecs
        jsr show_time
ga_input:
        jsr poll_input
        beq ga_loop
        cmp #$31                // "1".."3"
        bcc ga_other
        cmp #$34
        bcs ga_other
        sec
        sbc #$31
        cmp removed
        beq ga_loop
        rts
ga_other:
        cmp #$48                // "H": hint
        bne ga_notH
        jsr give_hint
        jmp ga_loop
ga_notH:
        jmp ga_loop

// first hint: the flag (or the country name); second: remove a wrong option
give_hint:
        lda hintlvl
        cmp #2
        bcs gh_done
        inc hintlvl
        cmp #1
        beq gh_fifty
.if (FLAG_HINT == 1) {
        jsr show_flag
}
        jmp show_hintline
gh_fifty:
        ldx #0                  // the first wrong option goes
gh_find:
        cpx anspos
        bne gh_got
        inx
        bne gh_find
gh_got:
        stx removed
        txa
        clc
        adc #21
        tay
        ldx #0
        jsr gotoxy
        ldx #33                 // blank the row up to the flag
        lda #$20
gh_blank:
        jsr CHROUT
        dex
        bne gh_blank
        jmp show_hintline
gh_done:
        rts

// row 24: what H does next (and the country, for the name hint)
show_hintline:
        ldx #0
        ldy #24
        jsr gotoxy
        ldx #TIME_COL-1
        lda #$20
sh_clear:
        jsr CHROUT
        dex
        bne sh_clear
        ldx #0
        ldy #24
        jsr gotoxy
        jsr player_tag          // "P1 " in a two-player game
.if (FLAG_HINT == 0) {
        lda hintlvl
        beq sh_text
        jsr get_recptr_ans      // the country as the first hint
        jsr print_country
        lda #$20
        jsr CHROUT
}
sh_text:
        ldx hintlvl
        lda hint_lo,x
        sta ptr
        lda hint_hi,x
        sta ptr+1
        jmp print_str

// row 24: the seconds (after the hint text; left of the flag)
show_time:
        ldx #TIME_COL
        ldy #24
        jsr gotoxy
        lda #<msg_time
        sta ptr
        lda #>msg_time
        sta ptr+1
        jsr print_str
        lda secs
        jsr print_dec8
        lda #$20
        jmp CHROUT

// --------------------------------------------------------------
// files: load_named X = file number (see file_tbl), stops on an error
// --------------------------------------------------------------
load_named:
        lda file_len,x
        sta fnlen
        lda file_nlo,x
        sta fnlo
        lda file_nhi,x
        sta fnhi
        lda file_alo,x
        sta addrlo
        lda file_ahi,x
        sta addrhi
        jsr load_file
        bcc ln_ok
        jmp load_err
ln_ok:
        rts

// load_file: fnlen/fnlo/fnhi = name, addrlo/addrhi = where; carry set = error
load_file:
        lda fnlen
        ldx fnlo
        ldy fnhi
        jsr SETNAM
        lda #2
        ldx #8
        ldy #0                  // SA=0: load to the X/Y address
        jsr SETLFS
        lda #0
        ldx addrlo
        ldy addrhi
        jsr LOAD
        php
        jsr close_ch
        plp
        rts

// --------------------------------------------------------------
// load_cities: CITIES to $6C40 (before the maps load there), then
// unpacked to CITYBUF: the build packs it (first byte 1, then the length
// and LZ data); CITYEDIT saves it plain, which is copied. Then SCORES,
// the right/wrong counts, are put into the records, and the records counted.
// --------------------------------------------------------------
load_cities:
        ldx #F_CITIES
        jsr load_named
        lda #<CITYBUF
        sta updst
        lda #>CITYBUF
        sta updst+1
        lda CITYLOAD
        cmp #1
        bne lc_plain
        lda #<(CITYLOAD+3)
        sta upsrc
        lda #>(CITYLOAD+3)
        sta upsrc+1
        clc
        lda CITYLOAD+1          // unpacked length
        adc #<CITYBUF
        sta upendlo
        lda CITYLOAD+2
        adc #>CITYBUF
        sta upendhi
        jsr unpack_lz
        jmp lc_scores
lc_plain:                       // copy CITYLOAD.. up to the LOAD end address ($AE)
        lda #<CITYLOAD
        sta upsrc
        lda #>CITYLOAD
        sta upsrc+1
        ldy #0
lc_copy:
        lda (upsrc),y
        sta (updst),y
        jsr um_src1
        jsr um_dst1
        lda upsrc+1
        cmp $AF
        bcc lc_copy
        lda upsrc
        cmp $AE
        bcc lc_copy
lc_scores:
        ldx #F_SCORES           // no SCORES file: the counts in CITIES stay
        jsr set_file
        jsr load_file
        bcs lc_count
        jsr lc_count            // numrec
        lda SCORESBUF           // only if it was saved for this many cities
        cmp numrec
        bne lc_done
        lda #<(SCORESBUF+1)
        sta ptr2
        lda #>(SCORESBUF+1)
        sta ptr2+1
        lda #0
        sta candidx
lc_merge:
        lda candidx
        jsr get_recptr
        ldx #0
lc_digit:
        ldy lc_offs,x           // the six digits: right, then wrong
        txa
        pha
        ldx #0
        lda (ptr2,x)
        sta (reclo),y
        inc ptr2
        bne lc_d2
        inc ptr2+1
lc_d2:
        pla
        tax
        inx
        cpx #6
        bne lc_digit
        inc candidx
        lda candidx
        cmp numrec
        bne lc_merge
        rts
lc_offs:
        .byte F_RIGHT, F_RIGHT+1, F_RIGHT+2, F_WRONG, F_WRONG+1, F_WRONG+2
lc_count:
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
        bne lc_loop
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
        jsr wait_continue
        jmp main

close_ch:
        lda #2
        jsr CLOSE
        jsr CLRCHN
        rts

// --------------------------------------------------------------
// save_file: fnlen/fnlo/fnhi = name ("@0:..."), addrlo/addrhi = start,
// X/Y = end + 1. saveok = 1 if the drive reports no error.
// --------------------------------------------------------------
save_file:
        stx tmp16lo
        sty tmp16hi
        lda fnlen
        ldx fnlo
        ldy fnhi
        jsr SETNAM
        lda #2
        ldx #8
        ldy #1
        jsr SETLFS
        lda addrlo
        sta ptr
        lda addrhi
        sta ptr+1
        ldx tmp16lo
        ldy tmp16hi
        lda #ptr                // A = zero-page pointer to the start address
        jsr SAVE
        lda #0
        rol                     // carry set = error
        eor #1
        sta saveok
        jsr close_ch
        jmp read_error

// save_scores: write SCORES (the six digits of every city's counts) on the
// plain text screen. Written byte by byte, so it needs no buffer; it is
// small, so saving is quick. saveok = 1 if the drive reports no error.
save_scores:
        jsr text_mode
        lda #$93
        jsr CHROUT
        say(15, 12, "SAVING...")
        ldx #F_SAVESCORES
        jsr set_file
        lda fnlen
        ldx fnlo
        ldy fnhi
        jsr SETNAM
        lda #2
        ldx #8
        ldy #2
        jsr SETLFS
        jsr OPEN
        bcs ss_fail
        ldx #2
        jsr CHKOUT
        bcs ss_fail
        lda #<SCORESBUF         // load address
        jsr CHROUT
        lda #>SCORESBUF
        jsr CHROUT
        lda numrec
        jsr CHROUT
        lda #0
        sta candidx
ss_rec:
        lda candidx
        jsr get_recptr
        ldx #0
ss_digit:
        ldy lc_offs,x
        lda (reclo),y
        jsr CHROUT
        inx
        cpx #6
        bne ss_digit
        inc candidx
        lda candidx
        cmp numrec
        bne ss_rec
        lda #1
        sta saveok
        jmp ss_close
ss_fail:
        lda #0
        sta saveok
ss_close:
        jsr CLRCHN
        lda #2
        jsr CLOSE
        jsr read_error
        jmp map_mode

// set_file: X = file number -> fnlen/fnlo/fnhi/addrlo/addrhi
set_file:
        lda file_len,x
        sta fnlen
        lda file_nlo,x
        sta fnlo
        lda file_nhi,x
        sta fnhi
        lda file_alo,x
        sta addrlo
        lda file_ahi,x
        sta addrhi
        rts

// read the drive's error channel; saveok = 0 unless it starts with "0"
read_error:
        lda #0
        jsr SETNAM
        lda #15
        ldx #8
        ldy #15
        jsr SETLFS
        jsr OPEN
        bcs re_fail
        ldx #15
        jsr CHKIN
        bcs re_fail
        jsr CHRIN               // first digit
        cmp #$30
        beq re_more
        lda #0
        sta saveok
re_more:
        jsr CHRIN               // drain the rest of the line
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

// read3: the 3-digit number at (reclo),y -> n16lo/n16hi
read3:
        lda #0
        sta n16lo
        sta n16hi
        ldx #3
r3_loop:
        lda n16lo               // n16 = n16 * 10
        sta tlo
        lda n16hi
        sta thi
        asl n16lo
        rol n16hi
        asl n16lo
        rol n16hi
        clc
        lda n16lo
        adc tlo
        sta n16lo
        lda n16hi
        adc thi
        sta n16hi
        asl n16lo
        rol n16hi
        lda (reclo),y
        sec
        sbc #$30
        clc
        adc n16lo
        sta n16lo
        bcc r3_next
        inc n16hi
r3_next:
        iny
        dex
        bne r3_loop
        rts

// weakness: keylo/keyhi = wrong - right + 1000 for the record at reclo
weakness:
        ldy #F_WRONG
        jsr read3
        clc
        lda n16lo
        adc #<1000
        sta keylo
        lda n16hi
        adc #>1000
        sta keyhi
        ldy #F_RIGHT
        jsr read3
        sec
        lda keylo
        sbc n16lo
        sta keylo
        lda keyhi
        sbc n16hi
        sta keyhi
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
// unpack_lz: LZ data at upsrc to updst until updst reaches upendlo/hi.
// A control byte $00-$7F is followed by that many + 1 literal bytes;
// $80-$FD means "copy (control - $80 + 4) bytes from (offset) bytes back
// in the output", with the offset in the next two bytes (low first);
// $FE and $FF are a run of $00 or $FF, with the length (0 = 256) next.
// The maps, the cities and the title are packed this way (prepare_data.ps1).
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
        lda #<(BITMAP+6400)
        sta upendlo
        lda #>(BITMAP+6400)
        sta upendhi
unpack_lz:
        ldy #0
        lda (upsrc),y
        jsr um_src1
        tax
        bmi lz_match
        inx                     // literal: control + 1 bytes
lz_lit:
        lda (upsrc),y
        sta (updst),y
        jsr um_src1
        jsr um_dst1
        dex
        bne lz_lit
        jmp lz_end
lz_match:
        cpx #$FE
        bcs lz_run
        txa
        and #$7F
        clc
        adc #4
        tax                     // length 4-129
        sec                     // ptr2 = updst - offset
        lda updst
        sbc (upsrc),y
        sta ptr2
        jsr um_src1
        lda updst+1
        sbc (upsrc),y
        sta ptr2+1
        jsr um_src1
lz_copy:
        lda (ptr2),y
        sta (updst),y
        inc ptr2
        bne lz_c2
        inc ptr2+1
lz_c2:
        jsr um_dst1
        dex
        bne lz_copy
        jmp lz_end
lz_run:                         // $FE: a run of $00, $FF: a run of $FF; then the length (0 = 256)
        txa
        and #1                  // $FE -> 0, $FF -> 1
        beq lz_r0
        lda #$FF
lz_r0:
        pha
        lda (upsrc),y           // the length
        jsr um_src1
        tax
        pla
lz_fill:
        sta (updst),y
        jsr um_dst1
        dex
        bne lz_fill
lz_end:
        lda updst+1
        cmp upendhi
        bcc unpack_lz
        bne lz_done
        lda updst
        cmp upendlo
        bcc unpack_lz
lz_done:
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
        lda #FLAGSPR/64
        sta SCREEN+$3F9
        lda #LANDSPR/64
        sta SCREEN+$3FA
        lda #0
        sta $D015               // sprites hidden until a round starts
        lda #%00000110          // sprites 1 (flag) and 2 (landmark): double size
        sta $D017
        sta $D01D
        lda #%00000010          // the flag is multicolour
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
        sta musicon
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

// top of the screen: bitmap on, flash the marker, count seconds, keyboard
irq_map:
        lda #1
        sta $D019
        lda #$3B                // bitmap mode
        sta $D011
        lda #$18                // screen $0400, bitmap $2000
        sta $D018
        jsr sfx_tick
        inc subsec              // seconds for the speed bonus (PAL: 50 frames)
        lda subsec
        cmp #50
        bcc im_flash
        lda #0
        sta subsec
        lda secs
        cmp #99
        bcs im_flash
        inc secs
im_flash:
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
// pick_ten: nrounds different cities. For each, three random candidates
// are drawn and the one answered wrong most often (wrong - right) wins,
// so the cities you find hard come up more.
// --------------------------------------------------------------
pick_ten:
        lda #0
        sta tmpx                // slot counter
pt_slot:
        lda #0
        sta bestlo
        sta besthi
        lda #3
        sta tries
pt_try:
        lda numrec
        jsr rndn
        ldy #0                  // not already chosen
pt_chk:
        cpy tmpx
        beq pt_new
        cmp tbl,y
        beq pt_try
        iny
        jmp pt_chk
pt_new:
        sta candidx
        jsr get_recptr
        jsr weakness
        lda keyhi               // key > best?
        cmp besthi
        bcc pt_next
        bne pt_take
        lda keylo
        cmp bestlo
        bcc pt_next
        beq pt_next
pt_take:
        lda keylo
        sta bestlo
        lda keyhi
        sta besthi
        lda candidx
        sta best
pt_next:
        dec tries
        bne pt_try
        ldy tmpx
        lda best
        sta tbl,y
        inc tmpx
        lda tmpx
        cmp nrounds
        bne pt_slot
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
// sprites: the marker (centre at 5,5 of the sprite), flag, landmark
// --------------------------------------------------------------
show_marker:
        clc
        lda pxlo
        adc #24-5               // screen left edge is sprite x 24
        sta $D000
        lda pxhi
        adc #0
        and #1
        sta tmpd
        lda $D010
        and #%11111110
        ora tmpd
        sta $D010
        clc
        lda pypix
        adc #50-5               // screen top is sprite y 50
        sta $D001
        lda $D015
        ora #1
        sta $D015
        rts

hide_marker:                    // all sprites
        lda #0
        sta $D015
        rts

// find_entry: the table at ptr (count byte, then FLAGLEN-byte entries that
// start with a 16-char name) -> ptr = entry whose name is in NAMEBUF.
// Carry set if there is none.
find_entry:
        ldy #0
        lda (ptr),y
        tax                     // number of entries
        inc ptr
        bne fe_start
        inc ptr+1
fe_start:
        cpx #0
        beq fe_none
fe_next:
        ldy #15
fe_cmp:
        lda (ptr),y
        cmp NAMEBUF,y
        bne fe_skip
        dey
        bpl fe_cmp
        clc
        rts
fe_skip:
        clc
        lda ptr
        adc #FLAGLEN
        sta ptr
        bcc fe_n2
        inc ptr+1
fe_n2:
        dex
        bne fe_next
fe_none:
        sec
        rts

// copy_name: 16 chars at (reclo),y -> NAMEBUF
copy_name:
        ldx #0
cn_loop:
        lda (reclo),y
        sta NAMEBUF,x
        iny
        inx
        cpx #16
        bne cn_loop
        rts

// copy_sprite: the 64 bytes at (ptr),20 -> (ptr2)
copy_sprite:
        ldy #20
        ldx #0
cs_loop:
        lda (ptr),y
        sta (ptr2,x)            // x stays 0
        inc ptr2
        iny
        cpy #84
        bne cs_loop
        rts

// show_flag: the flag of the answer's country as sprite 1, to the right
// of the answers. Call after show_marker (which rewrites $D010).
show_flag:
        jsr get_recptr_ans
        ldy #F_COUNTRY
        jsr copy_name
        lda #<FLAGS
        sta ptr
        lda #>FLAGS
        sta ptr+1
        jsr find_entry
        bcs sf_none
        ldy #16
        lda (ptr),y
        sta $D025               // bits 01
        iny
        lda (ptr),y
        sta $D028               // bits 10: sprite 1's own colour
        iny
        lda (ptr),y
        sta $D026               // bits 11
        lda #<FLAGSPR
        sta ptr2
        lda #>FLAGSPR
        sta ptr2+1
        jsr copy_sprite
        lda #<(24+272)          // x 272-319 on screen
        sta $D002
        lda #50+168             // text row 21
        sta $D003
        lda $D010
        ora #%00000010          // x is above 255
        sta $D010
        lda $D015
        ora #%00000010
        sta $D015
sf_none:
        rts

// show_landmark: if the answer city has a picture, show it next to the
// marker (sprite 2, hi-res, double size: 48 x 42 pixels)
show_landmark:
        jsr get_recptr_ans
        ldy #F_CITY
        jsr copy_name
        lda #<LANDMARKS
        sta ptr
        lda #>LANDMARKS
        sta ptr+1
        jsr find_entry
        bcs sl_none
        ldy #16
        lda (ptr),y
        sta $D029               // colour
        lda #<LANDSPR
        sta ptr2
        lda #>LANDSPR
        sta ptr2+1
        jsr copy_sprite
        // x: right of the marker, or left of it near the right edge
        lda pxhi
        bne sl_left
        lda pxlo
        cmp #250                // keep the 48-pixel picture on the map
        bcs sl_left
        clc
        lda pxlo
        adc #24+10
        sta tmp16lo
        lda #0
        adc #0
        sta tmp16hi
        jmp sl_y
sl_left:
        sec
        lda pxlo
        sbc #<(58-24)
        sta tmp16lo
        lda pxhi
        sbc #>(58-24)
        sta tmp16hi
sl_y:
        lda tmp16lo
        sta $D004
        lda $D010
        and #%11111011
        ldx tmp16hi
        beq sl_msb
        ora #%00000100
sl_msb:
        sta $D010
        // y: centred on the marker, kept on the map
        lda pypix
        sec
        sbc #21
        bcs sl_y1
        lda #0
sl_y1:
        cmp #160-42
        bcc sl_y2
        lda #160-42
sl_y2:
        clc
        adc #50
        sta $D005
        lda $D015
        ora #%00000100
        sta $D015
sl_none:
        rts

// --------------------------------------------------------------
// question + 3 options on rows 20..23
// --------------------------------------------------------------
print_question:
        ldx #0
        ldy #20
        jsr gotoxy
        lda regptr
        sta ptr
        lda regptr+1
        sta ptr+1
        jsr print_region
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

// print_region: the region name at ptr (a region table entry), trimmed
print_region:
        ldy #R_NAME+15
pr_trim:
        lda (ptr),y
        cmp #$20
        bne pr_end
        dey
        cpy #R_NAME
        bcs pr_trim
pr_end:
        iny
        sty count
        ldy #R_NAME
pr_name:
        cpy count
        bcs pr_done
        lda (ptr),y
        jsr CHROUT
        iny
        jmp pr_name
pr_done:
        rts

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
        sta n16lo
        lda #0
        sta n16hi
        // fall through

// print n16lo/n16hi (0..65535) as decimal, no leading zeros
print_dec16:
        lda #0
        sta pass                // 1 once a digit was printed
        ldx #4
pd_digit:
        lda #0
        sta tmpd                // digit
pd_sub:
        sec
        lda n16lo
        sbc pow10_lo,x
        tay
        lda n16hi
        sbc pow10_hi,x
        bcc pd_out
        sta n16hi
        sty n16lo
        inc tmpd
        jmp pd_sub
pd_out:
        lda tmpd
        bne pd_print
        lda pass
        bne pd_print
        cpx #0
        bne pd_skip
pd_print:
        lda #1
        sta pass
        lda tmpd
        clc
        adc #$30
        jsr CHROUT
pd_skip:
        dex
        bpl pd_digit
        rts
pow10_lo:
        .byte <1, <10, <100, <1000, <10000
pow10_hi:
        .byte >1, >10, >100, >1000, >10000

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
// title picture (multicolour bitmap in VIC bank 3)
// --------------------------------------------------------------
// load_title: TITLE (packed) to TITLEPACK, unpacked to $C000 and $E000;
// titleok = 1 if it worked. Without it the game shows a text title.
load_title:
        lda #0
        sta titleok
        ldx #F_TITLE
        jsr set_file
        jsr load_file
        bcs lt_done
        lda #<TITLEPACK
        sta upsrc
        lda #>TITLEPACK
        sta upsrc+1
        lda #<TITLESCR
        sta updst
        lda #>TITLESCR
        sta updst+1
        lda #<(TITLESCR+$800)
        sta upendlo
        lda #>(TITLESCR+$800)
        sta upendhi
        jsr unpack_lz           // colours
        lda #<TITLEBMP
        sta updst
        lda #>TITLEBMP
        sta updst+1
        lda #<(TITLEBMP+8000)
        sta upendlo
        lda #>(TITLEBMP+8000)
        sta upendhi
        sei                     // the bitmap is under the KERNAL ROM: the unpacker
        lda #$35                // reads back what it wrote, so the ROM goes off
        sta $01
        jsr unpack_lz
        lda #$36
        sta $01
        cli
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
// files: name, load address
// --------------------------------------------------------------
file_len:
        .byte fn_title_e-fn_title, fn_high_e-fn_high, fn_hs_e-fn_hs, fn_maps_e-fn_maps
        .byte fn_flags_e-fn_flags, fn_land_e-fn_land, fn_cities_e-fn_cities
        .byte fn_scores_e-fn_scores, fn_hs_e-fn_savehs, fn_savesc_e-fn_savesc
file_nlo:
        .byte <fn_title, <fn_high, <fn_hs, <fn_maps, <fn_flags, <fn_land, <fn_cities, <fn_scores, <fn_savehs, <fn_savesc
file_nhi:
        .byte >fn_title, >fn_high, >fn_hs, >fn_maps, >fn_flags, >fn_land, >fn_cities, >fn_scores, >fn_savehs, >fn_savesc
file_alo:
        .byte <TITLEPACK, <HIGHCODE, <HISCORES, <MAPS, <FLAGS, <LANDMARKS, <CITYLOAD, <SCORESBUF, <HISCORES, 0
file_ahi:
        .byte >TITLEPACK, >HIGHCODE, >HISCORES, >MAPS, >FLAGS, >LANDMARKS, >CITYLOAD, >SCORESBUF, >HISCORES, 0
fn_title:
        .text "TITLE"
fn_title_e:
fn_high:
        .text "HIGHCODE"
fn_high_e:
fn_savehs:
        .text "@0:"
fn_hs:
        .text "HISCORES"
fn_hs_e:
fn_maps:
        .text "MAPS"
fn_maps_e:
fn_flags:
        .text "FLAGS"
fn_flags_e:
fn_land:
        .text "LANDMARKS"
fn_land_e:
fn_cities:
        .text "CITIES"
fn_cities_e:
fn_scores:
        .text "SCORES"
fn_scores_e:
fn_savesc:
        .text "@0:SCORES,P,W"
fn_savesc_e:

// --------------------------------------------------------------
// strings
// --------------------------------------------------------------
msg_q:
        .text ": WHICH CITY IS MARKED?"
        .byte 0
msg_ferr:
        .text "FILE ERROR - CHECK DISK. SPACE=RETRY"
        .byte 0
msg_time:
        .text "TIME "
        .byte 0
hint_lo:
        .byte <msg_hint0, <msg_hint1, <msg_hint2
hint_hi:
        .byte >msg_hint0, >msg_hint1, >msg_hint2
msg_hint0:
        .text "H=HINT"
        .byte 0
msg_hint1:
        .text "H=50/50"
        .byte 0
msg_hint2:
        .byte 0

// player_tag: "P1 " or "P2 " in a two-player game
player_tag:
        lda players
        cmp #2
        bne pt_none
        lda #$50                // "P"
        jsr CHROUT
        lda curplayer
        clc
        adc #$31
        jsr CHROUT
        lda #$20
        jmp CHROUT
pt_none:
        rts

// player_tag2: "PLAYER 1" above the name entry in a two-player game
player_tag2:
        lda players
        cmp #2
        bne pt2_none
        say(4, 6, "PLAYER ")
        lda curplayer
        clc
        adc #$31
        jmp CHROUT
pt2_none:
        rts

// --------------------------------------------------------------
// find_on_map: the other game. The city's name is shown; the player moves
// a cross over the map with the cursor keys (or W A S D) and presses
// Return or Space. Points by the distance in km: under 50: 5, 150: 4,
// 300: 3, 600: 2, 1000: 1. Three or more count as a right answer.
// --------------------------------------------------------------
find_on_map:
        lda regptr              // "<REGION>: FIND"
        sta ptr
        lda regptr+1
        sta ptr+1
        ldx #0
        ldy #20
        jsr gotoxy
        jsr print_region
        jsr print_inline
        .text ": WHERE IS"
        .byte 0
        jsr get_recptr_ans
        ldx #2
        ldy #21
        jsr gotoxy
        jsr print_city
        lda #$2C
        jsr CHROUT
        lda #$20
        jsr CHROUT
        jsr print_country
        lda #$3F                // "?"
        jsr CHROUT
        say(0, 23, "MOVE: CURSOR KEYS OR W A S D")
        ldx #0
        ldy #24
        jsr gotoxy
        jsr player_tag
        jsr print_inline
        .text "RETURN OR SPACE: HERE"
        .byte 0
.if (FLAG_HINT == 1) {
        jsr show_flag
}
        ldx #62                 // the cross
fm_spr:
        lda cross_shape,x
        sta CROSSSPR,x
        dex
        bpl fm_spr
        lda #CROSSSPR/64
        sta SCREEN+$3FB
        lda #1                  // white: it shows on land and on sea
        sta $D02A
        lda #160
        sta crossxlo
        lda #0
        sta crossxhi
        sta holdcnt
        lda #80
        sta crossy
        jsr cross_pos
        lda $D015
        ora #%00001000
        sta $D015
        // move once a frame while a direction key is held
fm_frame:
        lda frames
        cmp lastframe
        beq fm_frame
        sta lastframe
        jsr fm_dir              // A = 0 none, 1 up, 2 down, 3 left, 4 right
        bne fm_move
        lda #0
        sta holdcnt
        jmp fm_key
fm_move:
        pha
        inc holdcnt
        bne fm_h
        dec holdcnt
fm_h:
        ldx #1                  // speed: 1, 2, then 4 pixels a frame
        lda holdcnt
        cmp #12
        bcc fm_step
        ldx #2
        cmp #30
        bcc fm_step
        ldx #4
fm_step:
        stx tmpd
        pla
        cmp #1
        bne fm_n1
        lda crossy              // up
        sec
        sbc tmpd
        bcs fm_y
        lda #0
        jmp fm_y
fm_n1:
        cmp #2
        bne fm_n2
        lda crossy              // down
        clc
        adc tmpd
        cmp #MAPROWS*8
        bcc fm_y
        lda #MAPROWS*8-1
fm_y:
        sta crossy
        jmp fm_moved
fm_n2:
        cmp #3
        bne fm_right
        sec                     // left
        lda crossxlo
        sbc tmpd
        sta crossxlo
        lda crossxhi
        sbc #0
        sta crossxhi
        bcs fm_moved
        lda #0
        sta crossxlo
        sta crossxhi
        jmp fm_moved
fm_right:
        clc
        lda crossxlo
        adc tmpd
        sta crossxlo
        lda crossxhi
        adc #0
        sta crossxhi
        beq fm_moved
        lda crossxlo            // keep it below 320
        cmp #<320
        bcc fm_moved
        lda #<319
        sta crossxlo
fm_moved:
        jsr cross_pos
fm_key:
        jsr GETIN
        cmp #$0D
        beq fm_done
        cmp #$20
        beq fm_done
        jmp fm_frame
fm_done:
        jsr map_distance        // distlo/hi = km
        jsr show_marker         // where the city really is
        jsr cross_pos           // (show_marker rewrote $D010)
        // points by distance
        ldx #0
fm_pts:
        lda distlo
        cmp km_lo,x
        lda disthi
        sbc km_hi,x
        bcc fm_got
        inx
        cpx #5
        bne fm_pts
fm_got:
        lda #5
        sec
        stx tmpd
        sbc tmpd
        sta gained
        cmp #3
        bcs fm_right_ans
        jsr answer_wrong
        jmp fm_text
fm_right_ans:
        jsr answer_right
fm_text:
        ldx #0
        ldy #20
        jsr gotoxy
        lda distlo
        sta n16lo
        lda disthi
        sta n16hi
        jsr print_dec16
        jsr print_inline
        .text " KM AWAY. +"
        .byte 0
        jmp print_gained
km_lo:
        .byte <50, <150, <300, <600, <1000
km_hi:
        .byte >50, >150, >300, >600, >1000

// fm_dir: the direction key held now (the KERNAL's key matrix code in $CB,
// shift in $028D): A = 0 none, 1 up, 2 down, 3 left, 4 right
fm_dir:
        lda $CB
        cmp #9                  // W
        beq fd_up
        cmp #13                 // S
        beq fd_down
        cmp #10                 // A
        beq fd_left
        cmp #18                 // D
        beq fd_right
        cmp #7                  // cursor up/down
        bne fd_lr
        lda $028D
        and #1
        bne fd_up
fd_down:
        lda #2
        rts
fd_lr:
        cmp #2                  // cursor left/right
        bne fd_none
        lda $028D
        and #1
        bne fd_left
fd_right:
        lda #4
        rts
fd_up:
        lda #1
        rts
fd_left:
        lda #3
        rts
fd_none:
        lda #0
        rts

// cross_pos: the cross sprite (3) at crossx/crossy; its centre is 5 pixels in
cross_pos:
        clc
        lda crossxlo
        adc #24-5
        sta $D006
        lda crossxhi
        adc #0
        beq cp_lo
        lda $D010
        ora #%00001000
        bne cp_msb
cp_lo:
        lda $D010
        and #%11110111
cp_msb:
        sta $D010
        clc
        lda crossy
        adc #50-5
        sta $D007
        rts

// map_distance: km between the cross and the city, on this region's map.
//   a = |dx| * DX * cos(latitude)   b = |dy| * DY   (hundredths of a degree)
//   d = max(a, b) + 3/8 * min(a, b)  (a close fit for the straight distance)
//   km = d * 1.11                    (one degree is 111 km)
map_distance:
        sec                     // |dx| in pixels
        lda crossxlo
        sbc pxlo
        sta m16lo
        lda crossxhi
        sbc pxhi
        sta m16hi
        bcs md_dxpos
        sec
        lda #0
        sbc m16lo
        sta m16lo
        lda #0
        sbc m16hi
        sta m16hi
md_dxpos:
        lda regdx
        sta mb
        jsr mul16x8             // r24 = |dx| * DX
        lda r24
        sta m16lo
        lda r24+1
        sta m16hi
        lda lathi               // |latitude| in degrees -> cos
        bpl md_latpos
        sec
        lda #0
        sbc latlo
        sta dvd
        lda #0
        sbc lathi
        sta dvdh
        jmp md_deg
md_latpos:
        lda latlo
        sta dvd
        lda lathi
        sta dvdh
md_deg:
        lda #100
        sta dvs
        lda #0
        sta dvsh
        jsr div16
        ldx dvd
        lda cos_tbl,x
        sta mb
        jsr mul16x8             // r24 = a * cos * 256
        lda r24+1
        sta alo
        lda r24+2
        sta ahi
        lda crossy              // |dy| * DY
        sec
        sbc pypix
        bcs md_dypos
        eor #$FF
        adc #1
md_dypos:
        sta ma
        lda regdy
        sta mb
        jsr mul8
        lda res
        sta blo
        lda resh
        sta bhi
        // d = max + 3/8 min
        lda alo
        cmp blo
        lda ahi
        sbc bhi
        bcs md_amax             // a >= b
        lda alo                 // swap, so a is the larger
        ldx blo
        sta blo
        stx alo
        lda ahi
        ldx bhi
        sta bhi
        stx ahi
md_amax:
        lsr bhi                 // b/4
        ror blo
        lsr bhi
        ror blo
        lda blo
        sta tlo
        lda bhi
        sta thi
        lsr thi                 // b/8
        ror tlo
        clc
        lda alo
        adc blo
        sta alo
        lda ahi
        adc bhi
        sta ahi
        clc
        lda alo
        adc tlo
        sta alo
        sta distlo
        lda ahi
        adc thi
        sta ahi
        sta disthi
        // km = d + d/10 + d/100
        ldx #10
        jsr md_addpart
        ldx #100
md_addpart:
        lda alo
        sta dvd
        lda ahi
        sta dvdh
        stx dvs
        lda #0
        sta dvsh
        jsr div16
        clc
        lda distlo
        adc dvd
        sta distlo
        lda disthi
        adc dvdh
        sta disthi
        rts

// mul16x8: m16lo/hi * mb -> r24 (3 bytes)
mul16x8:
        lda #0
        sta r24
        sta r24+1
        sta r24+2
        ldx #8
m16_loop:
        asl r24
        rol r24+1
        rol r24+2
        asl mb
        bcc m16_next
        clc
        lda r24
        adc m16lo
        sta r24
        lda r24+1
        adc m16hi
        sta r24+1
        lda r24+2
        adc #0
        sta r24+2
m16_next:
        dex
        bne m16_loop
        rts

// cos of 0-90 degrees, times 255
cos_tbl:
.for (var i = 0; i <= 90; i++) {
        .byte round(255 * cos(toRadians(i)))
}

// the map game's cross: 11 x 11 with an open centre
cross_shape:
        .byte $04,$00,$00
        .byte $04,$00,$00
        .byte $04,$00,$00
        .byte $04,$00,$00
        .byte $00,$00,$00
        .byte $F1,$E0,$00
        .byte $00,$00,$00
        .byte $04,$00,$00
        .byte $04,$00,$00
        .byte $04,$00,$00
        .byte $04,$00,$00
        .fill 30, 0

.assert "The main program must end below the bitmap at $2000", * <= BITMAP, true

// ==============================================================
// Second part: loaded from HIGHCODE to $C800
// ==============================================================
.segment HighCode [start=HIGHCODE, max=$CFFF, outPrg="highcode.prg"]

// --------------------------------------------------------------
// title_loop: the title picture and the high-score table take turns
// (8 seconds each) with music, until Space. S shows the stats.
// --------------------------------------------------------------
title_loop:
        jsr music_on
tl_title:
        lda titleok
        beq tl_text
        jsr title_on
        jmp tl_wait1
tl_text:
        jsr title_off
        lda #<msg_title
        sta ptr
        lda #>msg_title
        sta ptr+1
        jsr print_str
tl_wait1:
        jsr wait_8s
        bcs tl_go
        jsr title_off
        jsr show_hiscores
        jsr wait_8s
        bcs tl_go
        jmp tl_title
tl_go:
        cmp #$53                // "S": stats, then back
        bne tl_play
        jsr title_off
        jsr show_stats
        jsr wait_continue
        jmp tl_title
tl_play:
        jmp music_off

// wait_8s: carry set and A = key when Space, Return or S comes within 8 s
wait_8s:
        lda #<400               // jiffies: the KERNAL clock ticks 60 times a second
        sta waitlo
        lda #>400
        sta waithi
        lda $A2
        sta lastkey
w8_loop:
        lda $A2
        cmp lastkey
        beq w8_in
        sta lastkey
        lda waitlo
        bne w8_dec
        dec waithi
w8_dec:
        dec waitlo
        lda waitlo
        ora waithi
        bne w8_in
        clc
        rts
w8_in:
        jsr poll_input
        cmp #$20
        beq w8_yes
        cmp #$0D
        beq w8_yes
        cmp #$53                // "S"
        beq w8_yes
        jmp w8_loop
w8_yes:
        sec
        rts

// --------------------------------------------------------------
// high scores
// --------------------------------------------------------------
show_hiscores:
        ldx #12
        ldy #1
        jsr gotoxy
        lda #<msg_hstitle
        sta ptr
        lda #>msg_hstitle
        sta ptr+1
        jsr print_str
        lda #0
        sta tmpx
hs_row:
        lda tmpx                // row 4 + 2 * entry
        asl
        clc
        adc #4
        tay
        ldx #9
        jsr gotoxy
        lda tmpx
        clc
        adc #1
        cmp #10
        bcs hs_num
        pha
        lda #$20
        jsr CHROUT
        pla
hs_num:
        jsr print_dec8
        lda #$2E                // "."
        jsr CHROUT
        lda #$20
        jsr CHROUT
        jsr hs_entry            // ptr2 = entry tmpx
        ldy #0
hs_name:
        lda (ptr2),y
        jsr CHROUT
        iny
        cpy #HSNAME
        bne hs_name
        lda #$20
        jsr CHROUT
        jsr CHROUT
        ldy #HSNAME
        lda (ptr2),y
        jsr print_dec8
        inc tmpx
        lda tmpx
        cmp #10
        bne hs_row
        ldx #8
        ldy #24
        jsr gotoxy
        lda #<msg_hskeys
        sta ptr
        lda #>msg_hskeys
        sta ptr+1
        jmp print_str

// hs_entry: ptr2 = HISCORES + tmpx * HSLEN
hs_entry:
        lda tmpx
        asl
        asl                     // *4
        sta tmpd
        asl                     // *8
        clc
        adc tmpd                // *12
        clc
        adc #<HISCORES
        sta ptr2
        lda #>HISCORES
        adc #0
        sta ptr2+1
        rts

// check_hiscore: hspos = first place whose points are lower than score
check_hiscore:
        lda #0
        sta tmpx
ch_loop:
        jsr hs_entry
        ldy #HSNAME
        lda (ptr2),y
        cmp score
        bcc ch_found
        inc tmpx
        lda tmpx
        cmp #10
        bne ch_loop
        lda #$FF
        sta hspos
        rts
ch_found:
        lda tmpx
        sta hspos
        rts

// enter_hiscore: type a name, put it in the table at hspos, save, show it
enter_hiscore:
        jsr text_mode
        lda #$93
        jsr CHROUT
        jsr player_tag2         // "PLAYER 1" in a two-player game
        ldx #4
        ldy #8
        jsr gotoxy
        lda #<msg_entername
        sta ptr
        lda #>msg_entername
        sta ptr+1
        jsr print_str
        lda #0
        sta namelen
        ldx #HSNAME-1
        lda #$20
eh_clear:
        sta NAMEIN,x
        dex
        bpl eh_clear
eh_show:
        ldx #15
        ldy #11
        jsr gotoxy
        ldx #0
eh_shown:
        lda NAMEIN,x
        cpx namelen
        bne eh_ch
        lda #$A4                // the cursor: an underscore block
eh_ch:
        jsr CHROUT
        inx
        cpx #HSNAME
        bne eh_shown
        lda #$20
        jsr CHROUT
eh_key:
        jsr poll_input
        beq eh_key
        cmp #$0D                // Return: done
        beq eh_done
        cmp #$14                // Delete
        bne eh_add
        ldx namelen
        beq eh_key
        dex
        stx namelen
        lda #$20
        sta NAMEIN,x
        jmp eh_show
eh_add:
        cmp #$20
        bcc eh_key
        cmp #$5B                // space, digits, signs and A-Z
        bcs eh_key
        ldx namelen
        cpx #HSNAME
        bcs eh_key
        sta NAMEIN,x
        inc namelen
        jmp eh_show
eh_done:
        // move entries hspos..8 down one place
        lda hspos
        cmp #9
        beq eh_put
        lda #8
        sta tmpx
eh_move:
        jsr hs_entry            // ptr2 = entry tmpx
        lda ptr2
        clc
        adc #HSLEN
        sta ptr
        lda ptr2+1
        adc #0
        sta ptr+1               // ptr = entry tmpx+1
        ldy #HSLEN-1
eh_mv:
        lda (ptr2),y
        sta (ptr),y
        dey
        bpl eh_mv
        lda tmpx
        cmp hspos
        beq eh_put
        dec tmpx
        jmp eh_move
eh_put:
        lda hspos
        sta tmpx
        jsr hs_entry
        ldy #HSNAME-1
eh_cp:
        lda NAMEIN,y
        sta (ptr2),y
        dey
        bpl eh_cp
        ldy #HSNAME
        lda score
        sta (ptr2),y
        iny
        lda #0
        sta (ptr2),y
        // save the table
        lda #$93
        jsr CHROUT
        ldx #F_SAVEHISCORES
        jsr set_file
        ldx #<(HISCORES+10*HSLEN)
        ldy #>(HISCORES+10*HSLEN)
        jsr save_file
        lda #$93
        jsr CHROUT
        jsr show_hiscores
        jmp wait_continue

// --------------------------------------------------------------
// stats: the ten cities you got wrong most often (wrong - right), and
// the totals. The bitmap area marks the cities already listed.
// --------------------------------------------------------------
show_stats:
        ldx #7
        ldy #1
        jsr gotoxy
        lda #<msg_stattitle
        sta ptr
        lda #>msg_stattitle
        sta ptr+1
        jsr print_str
        // totals, and clear the marks
        lda #0
        sta totrlo
        sta totrhi
        sta totwlo
        sta totwhi
        sta candidx
ss_tot:
        lda candidx
        cmp numrec
        bcs ss_totdone
        tax
        lda #0
        sta BITMAP,x
        lda candidx
        jsr get_recptr
        ldy #F_RIGHT
        jsr read3
        clc
        lda totrlo
        adc n16lo
        sta totrlo
        lda totrhi
        adc n16hi
        sta totrhi
        ldy #F_WRONG
        jsr read3
        clc
        lda totwlo
        adc n16lo
        sta totwlo
        lda totwhi
        adc n16hi
        sta totwhi
        inc candidx
        jmp ss_tot
ss_totdone:
        lda #3
        sta ctrow               // screen row
ss_pick:
        lda #0
        sta bestlo
        sta besthi
        lda #$FF
        sta best
        lda #0
        sta candidx
ss_scan:
        lda candidx
        cmp numrec
        bcs ss_scanned
        tax
        lda BITMAP,x
        bne ss_skip
        lda candidx
        jsr get_recptr
        ldy #F_WRONG            // only cities with a wrong answer
        jsr read3
        lda n16lo
        ora n16hi
        beq ss_skip
        jsr weakness
        lda keyhi
        cmp besthi
        bcc ss_skip
        bne ss_take
        lda keylo
        cmp bestlo
        bcc ss_skip
        beq ss_skip
ss_take:
        lda keylo
        sta bestlo
        lda keyhi
        sta besthi
        lda candidx
        sta best
ss_skip:
        inc candidx
        jmp ss_scan
ss_scanned:
        lda best
        cmp #$FF
        beq ss_end
        tax
        lda #1
        sta BITMAP,x
        lda best
        jsr get_recptr
        ldx #0
        ldy ctrow
        jsr gotoxy
        jsr print_city
        ldx #17
        ldy ctrow
        jsr gotoxy
        jsr print_country
        ldx #33                 // wrong / right
        ldy ctrow
        jsr gotoxy
        ldy #F_WRONG
        jsr read3
        jsr print_dec16
        lda #$2F                // "/"
        jsr CHROUT
        ldy #F_RIGHT
        jsr read3
        jsr print_dec16
        inc ctrow
        inc ctrow
        lda ctrow
        cmp #23
        bcs ss_end
        jmp ss_pick
ss_end:
        lda ctrow
        cmp #3
        bne ss_totals
        ldx #6                  // nothing wrong yet
        ldy #10
        jsr gotoxy
        lda #<msg_nowrong
        sta ptr
        lda #>msg_nowrong
        sta ptr+1
        jsr print_str
ss_totals:
        ldx #2
        ldy #23
        jsr gotoxy
        lda #<msg_totals
        sta ptr
        lda #>msg_totals
        sta ptr+1
        jsr print_str
        lda totrlo
        sta n16lo
        lda totrhi
        sta n16hi
        jsr print_dec16
        lda #<msg_totals2
        sta ptr
        lda #>msg_totals2
        sta ptr+1
        jsr print_str
        lda totwlo
        sta n16lo
        lda totwhi
        sta n16hi
        jsr print_dec16
        lda #<msg_totals3
        sta ptr
        lda #>msg_totals3
        sta ptr+1
        jmp print_str

// --------------------------------------------------------------
// title music: two voices (2: melody, 3: bass) from the KERNAL interrupt
// (60 times a second). A tune is note, ticks pairs; note 0 is a rest,
// $FF starts the tune again. Notes count semitones from C2 = 1.
// --------------------------------------------------------------
music_on:
        lda musicon             // already playing: carry on
        bne mo_done
        sei
        lda #0
        sta mus1pos
        sta mus1pos+1
        sta mus2pos
        sta mus2pos+1
        lda #1
        sta mus1time
        sta mus2time
        lda #$0F
        sta $D418
        lda #$00                // voice 2: pulse, short attack
        sta $D409
        lda #$08
        sta $D40A
        lda #$09
        sta $D40C
        lda #$A6
        sta $D40D
        lda #$08                // voice 3: triangle bass
        sta $D413
        lda #$C8
        sta $D414
        lda #1
        sta musicon
        lda #<music_irq
        sta $0314
        lda #>music_irq
        sta $0315
        cli
        rts
mo_done:
        rts

music_off:
        sei
        lda #0
        sta musicon
        sta $D40B
        sta $D412
        lda #$31
        sta $0314
        lda #$EA
        sta $0315
        cli
        rts

music_irq:
        lda musicon
        beq mi_done
        // voice 2
        dec mus1time
        bne mi_v2gate
        lda #<tune_melody
        sta mptr2
        lda #>tune_melody
        sta mptr2+1
        ldx #0
        jsr mus_next
        sta mus1time
        lda tmpfreq
        sta $D407
        lda tmpfreq+1
        sta $D408
        lda tmpgate
        ora #$40
        sta $D40B
        jmp mi_v3
mi_v2gate:
        lda mus1time            // gate off just before the next note
        cmp #3
        bne mi_v3
        lda #$40
        sta $D40B
mi_v3:
        dec mus2time
        bne mi_v3gate
        lda #<tune_bass
        sta mptr2
        lda #>tune_bass
        sta mptr2+1
        ldx #2
        jsr mus_next
        sta mus2time
        lda tmpfreq
        sta $D40E
        lda tmpfreq+1
        sta $D40F
        lda tmpgate
        ora #$10
        sta $D412
        jmp mi_done
mi_v3gate:
        lda mus2time
        cmp #3
        bne mi_done
        lda #$10
        sta $D412
mi_done:
        jmp $EA31

// mus_next: the next note of the tune at mptr2, position mus1pos+X.
// Sets tmpfreq and tmpgate (1, or 0 for a rest); returns A = ticks.
mus_next:
        clc
        lda mptr2
        adc mus1pos,x
        sta mptr
        lda mptr2+1
        adc mus1pos+1,x
        sta mptr+1
        ldy #0
        lda (mptr),y
        cmp #$FF                // the end: from the start again
        bne mn_note
        lda #0
        sta mus1pos,x
        sta mus1pos+1,x
        jmp mus_next
mn_note:
        pha
        clc                     // two bytes on
        lda mus1pos,x
        adc #2
        sta mus1pos,x
        lda mus1pos+1,x
        adc #0
        sta mus1pos+1,x
        pla
        beq mn_rest
        asl
        tay
        lda note_freq-2,y
        sta tmpfreq
        lda note_freq-1,y
        sta tmpfreq+1
        lda #1
        sta tmpgate
        jmp mn_len
mn_rest:
        lda #0
        sta tmpgate
mn_len:
        ldy #1
        lda (mptr),y
        rts
tmpfreq:
        .word 0
tmpgate:
        .byte 0

// SID frequencies (PAL) for C2 upwards
note_freq:
.for (var i = 0; i < 60; i++) {
        .word round(65.406 * pow(2, i / 12) * 16777216 / 985248)
}

// the tune and the text title come from config.asm
tune_melody:
        tune_melody_data()
tune_bass:
        tune_bass_data()

msg_title:
        title_text()
msg_hstitle:
        .text "HIGH SCORES"
        .byte 0
msg_hskeys:
        .text "SPACE=PLAY  S=YOUR STATS"
        .byte 0
msg_entername:
        .text "NEW HIGH SCORE! TYPE YOUR NAME:"
        .byte 0
msg_stattitle:
        .text "THE CITIES YOU MISS MOST"
        .byte 0
msg_nowrong:
        .text "NO WRONG ANSWERS YET. WELL DONE!"
        .byte 0
msg_totals:
        .text "ALL GAMES: "
        .byte 0
msg_totals2:
        .text " RIGHT, "
        .byte 0
msg_totals3:
        .text " WRONG"
        .byte 0
