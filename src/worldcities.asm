; ==============================================================
; WORLDCITIES - a "name the capital" game for the Commodore 64
;
; Load order on disk (device 8):
;   CHARMAP - raw 1000 bytes, map screen codes (see tools/mask2c64.py)
;   COLMAP  - raw 1000 bytes, map colours
;   CITIES  - raw city records, 40 bytes each (see src/cityedit.asm)
;
; Assemble: acme --cpu 6510 src/worldcities.asm
; ==============================================================

!to "worldcities.prg", cbm
!cpu 6510

; ---------------- KERNAL ----------------
CHROUT  = $FFD2
GETIN   = $FFE4
PLOT    = $FFF0
LOAD    = $FFD5
SETNAM  = $FFBD
SETLFS  = $FE00
CLOSE   = $FFC3
CLRCHN  = $FFCC

; ---------------- memory ----------------
CITYBUF = $6000          ; city data buffer
MAPBUF  = $5000          ; CHARMAP load buffer
COLBUF  = $5400          ; COLMAP load buffer
RECLEN  = 40             ; 39 chars + CR
RECMAX  = 160            ; max records (8 KB buffer)
ROUNDS  = 10             ; cities per game
MAPROWS = 20             ; map occupies screen rows 0..19

; ---------------- zero page (math + pointers) ----------------
dvd     = $FB            ; dividend / quotient
dvdh    = $FC
dvs     = $FD           ; divisor
dvsh    = $FE
reclo   = $FB           ; record pointer (aliases dvd, used at other times)
rechi   = $FC

ptr     = $02            ; temp pointer

; ---------------- variables (cassette buffer) ----------------
seed    = $33C
numrec  = $33E
score   = $33F
round   = $340
ansidx  = $341
anspos  = $342
cellx   = $343
celly   = $344
latlo   = $345
lathi   = $346
lonlo   = $347
lonhi   = $348
negf    = $34B
numlo   = $34C
numhi   = $34D
tmpd    = $34E
tlo     = $34F
thi     = $350
rem     = $351
remh    = $352
ma      = $353
mb      = $354
res     = $355
resh    = $356
msavc   = $357
msavo   = $358
moff    = $359
opt     = $35A
tmpx    = $35D
idxtmp  = $35E
count   = $35F
tbl     = $360
ctrow   = $36A

; ==============================================================
; BASIC stub: 10 SYS2062
; ==============================================================
*=$0801
        !byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$32,$00,$00,$00
*=$080D

main:
        lda #0
        sta $D020               ; border black
        sta $D021               ; background black
        lda #$93                ; clear screen
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

        lda $DC04               ; seed RNG from CIA timer
        sta seed
        lda $DC05
        eor seed
        sta seed

        jsr load_map
        jsr load_cities
        lda numrec
        cmp #10
        bcc err_few

        lda #0
        sta score
        sta round
        jsr pick_ten

roundloop:
        jsr clear_text
        ldx round
        lda tbl,x
        sta ansidx
        jsr get_recptr_ans     ; reclo/rechi -> record of ansidx
        jsr parse_coords
        jsr calc_cell
        jsr draw_marker
        jsr choose_options
        jsr print_question
        jsr get_answer          ; A = 1..3
        sec
        sbc #1
        cmp anspos
        beq was_correct

        ; ----- wrong answer -----
        jsr restore_marker
        ldx #0
        ldy #24
        jsr gotoxy
        lda #<msg_wrong
        sta ptr
        lda #>msg_wrong
        sta ptr+1
        jsr print_str
        lda ansidx
        jsr get_recptr
        jsr print_city
        lda #$20
        jsr CHROUT
        lda #$28                ; "("
        jsr CHROUT
        jsr print_country
        lda #$29                ; ")"
        jsr CHROUT
        jmp fb_wait

was_correct:
        inc score
        jsr restore_marker
        ldx #0
        ldy #24
        jsr gotoxy
        lda #<msg_correct
        sta ptr
        lda #>msg_correct
        sta ptr+1
        jsr print_str
        lda ansidx
        jsr get_recptr
        jsr print_city
        lda #$20
        jsr CHROUT
        lda #$28
        jsr CHROUT
        jsr print_country
        lda #$29
        jsr CHROUT

fb_wait:
        jsr GETIN
        cmp #$20
        bne fb_wait

        inc round
        lda round
        cmp #ROUNDS
        bne roundloop

        ; ----- game over -----
        jsr clear_text
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
        lda #$2F                ; "/"
        jsr CHROUT
        lda #$30+ROUNDS
        jsr CHROUT
over_wait:
        jsr GETIN
        cmp #$20
        bne over_wait
        jmp main

; --------------------------------------------------------------
; err: not enough cities
; --------------------------------------------------------------
err_few:
        jsr clear_text
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

; --------------------------------------------------------------
; load CHARMAP + COLMAP and build the map on screen
; --------------------------------------------------------------
load_map:
        lda #7                  ; "CHARMAP"
        ldx #<fn_charmap
        ldy #>fn_charmap
        jsr SETNAM
        lda #2
        ldx #8
        ldy #2                  ; SA=2: raw load to XY address
        jsr SETLFS
        lda #0
        ldx #<MAPBUF
        ldy #>MAPBUF
        jsr LOAD
        bcs load_err
        jsr close_ch
        lda #6                  ; "COLMAP"
        ldx #<fn_colmap
        ldy #>fn_colmap
        jsr SETNAM
        lda #2
        ldx #8
        ldy #2
        jsr SETLFS
        lda #0
        ldx #<COLBUF
        ldy #>COLBUF
        jsr LOAD
        bcs load_err
        jsr close_ch

        ; copy 1024 bytes CHARMAP -> screen RAM
        ldx #0
lm_c1:
        lda MAPBUF,x
        sta $0400,x
        lda MAPBUF+$0100,x
        sta $0500,x
        lda MAPBUF+$0200,x
        sta $0600,x
        lda MAPBUF+$0300,x
        sta $0700,x
        inx
        bne lm_c1
        ; copy 1024 bytes COLMAP -> colour RAM
        ldx #0
lm_c2:
        lda COLBUF,x
        sta $D800,x
        lda COLBUF+$0100,x
        sta $D900,x
        lda COLBUF+$0200,x
        sta $DA00,x
        lda COLBUF+$0300,x
        sta $DB00,x
        inx
        bne lm_c2
        rts

; --------------------------------------------------------------
; load CITIES and count records
; --------------------------------------------------------------
load_cities:
        lda #6                  ; "CITIES"
        ldx #<fn_cities
        ldy #>fn_cities
        jsr SETNAM
        lda #2
        ldx #8
        ldy #2
        jsr SETLFS
        lda #0
        ldx #<CITYBUF
        ldy #>CITYBUF
        jsr LOAD
        bcs load_err
        jsr close_ch
        ; count records until zero byte or RECMAX
        lda #<CITYBUF
        sta ptr
        lda #>CITYBUF
        sta ptr+1
        ldx #0                  ; record count
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

; --------------------------------------------------------------
; choose ROUNDS distinct random record indices
; --------------------------------------------------------------
pick_ten:
        lda #0
        sta tmpx              ; slot counter (rndn clobbers X)
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

; --------------------------------------------------------------
; options: correct city + 2 random distractors, answer shuffled
; --------------------------------------------------------------
choose_options:
        lda #3
        jsr rndn
        sta anspos              ; 0..2
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

; --------------------------------------------------------------
; record pointer for the answer (reclo/rechi)
; --------------------------------------------------------------
get_recptr_ans:
        lda ansidx
        ; fall through

; --------------------------------------------------------------
; get_recptr: A = record index -> reclo/rechi = CITYBUF + A*RECLEN
; --------------------------------------------------------------
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

; --------------------------------------------------------------
; parse latitude/longitude of record at reclo/rechi
; --------------------------------------------------------------
parse_coords:
        lda reclo
        clc
        adc #25                 ; lat field
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
        adc #32                 ; lon field
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

; --------------------------------------------------------------
; parse a signed decimal number at ptr, e.g. "-55.68"
; result (centi-degrees, signed) in numlo/numhi
; --------------------------------------------------------------
parse_num:
        ldy #0
        lda #0
        sta negf
        sta numlo
        sta numhi
pn_sp:
        lda (ptr),y
        cmp #$20                ; skip padding spaces
        bne pn_sign
        iny
        jmp pn_sp
pn_sign:
        cmp #$2D                ; "-"
        bne pn_int
        lda #1
        sta negf
        iny
pn_int:
        lda (ptr),y
        sec
        sbc #$30
        cmp #10
        bcs pn_dot
        sta tmpd
        lda numlo
        sta tlo
        lda numhi
        sta thi
        asl numlo
        rol numhi
        asl numlo
        rol numhi
        asl numlo
        rol numhi              ; num*8
        clc
        lda numlo
        adc tlo
        sta numlo
        lda numhi
        adc thi
        sta numhi              ; num*9
        clc
        lda numlo
        adc tmpd
        sta numlo
        bcc pn_i1
        inc numhi
pn_i1:
        iny
        jmp pn_int
pn_dot:
        lda (ptr),y
        cmp #$2E                ; "."
        bne pn_fin
        iny
        lda #0
        sta tmpd
        ; first decimal digit
        lda (ptr),y
        sec
        sbc #$30
        cmp #10
        bcs pn_fin
        sta tmpd
        asl tmpd
        asl tmpd
        asl tmpd               ; d*8
        lda tmpd
        lsr a
        lsr a                  ; A = d*2
        clc
        adc tmpd
        sta tmpd               ; d*10
        iny
        ; second decimal digit
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
        jsr mul8                ; res = degrees * 100
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
pn_fin:
        rts

; --------------------------------------------------------------
; lat/lon -> map cell
;   cellx = (lon + 18000) / 900   (0..40, clamp 39)
;   celly = (9000 - lat) / 720    (0..25, clamp MAPROWS-1)
; (centi-degrees, linear equirectangular mapping)
; --------------------------------------------------------------
calc_cell:
        clc
        lda lonlo
        adc #$50               ; 18000 = $4650
        sta dvd
        lda lonhi
        adc #$46
        sta dvdh
        lda #<900
        sta dvs
        lda #>900
        sta dvsh
        jsr div16
        lda dvd
        cmp #40
        bcc cc1
        lda #39
cc1:
        sta cellx
        sec
        lda #$28               ; 9000 = $2328
        sbc latlo
        sta dvd
        lda #$23
        sbc lathi
        sta dvdh
        lda #<720
        sta dvs
        lda #>720
        sta dvsh
        jsr div16
        lda dvd
        cmp #MAPROWS
        bcc cc2
        lda #MAPROWS-1
cc2:
        sta celly
        rts

; --------------------------------------------------------------
; marker: draw / restore at screen cell
; --------------------------------------------------------------
draw_marker:
        lda #0
        sta moff
        ldx celly
        beq dm2
        lda #40
dm1:
        clc
        adc moff
        sta moff
        dex
        bne dm1
dm2:
        clc
        lda moff
        adc cellx
        sta moff
        tay
        lda $0400,y
        sta msavc
        lda $D800,y
        sta msavo
        lda #$A0               ; reverse space = solid block
        sta $0400,y
        lda #2                 ; red
        sta $D800,y
        rts

restore_marker:
        ldy moff
        lda msavc
        sta $0400,y
        lda msavo
        sta $D800,y
        rts

; --------------------------------------------------------------
; question + 3 options on rows 20..23
; --------------------------------------------------------------
print_question:
        ldx #0
        ldy #20
        jsr gotoxy
        lda #<msg_q
        sta ptr
        lda #>msg_q
        sta ptr+1
        jsr print_str

        lda opt
        jsr get_recptr
        ldx #0
        ldy #21
        jsr gotoxy
        lda #$31
        jsr CHROUT
        lda #$20
        jsr CHROUT
        jsr print_city

        lda opt+1
        jsr get_recptr
        ldx #0
        ldy #22
        jsr gotoxy
        lda #$32
        jsr CHROUT
        lda #$20
        jsr CHROUT
        jsr print_city

        lda opt+2
        jsr get_recptr
        ldx #0
        ldy #23
        jsr gotoxy
        lda #$33
        jsr CHROUT
        lda #$20
        jsr CHROUT
        jsr print_city
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

; --------------------------------------------------------------
; print city (field 0, 13 chars) / country (field 14, 10 chars)
; of record at reclo/rechi, trailing spaces trimmed
; --------------------------------------------------------------
print_city:
        jsr trim_helper
        ldy #0
pc_l:
        lda (reclo),y
        jsr CHROUT
        iny
        cpy count
        bcc pc_l
        rts

print_country:
        jsr trim_helper_country
        ldy #14
pco_l:
        lda (reclo),y
        jsr CHROUT
        iny
        cpy count
        bcc pco_l
        rts

trim_helper:
        ldy #12
th_l:
        lda (reclo),y
        cmp #$20
        bne th_ok
        dey
        bpl th_l
        ldy #$FF              ; empty field
th_ok:
        iny
        sty count
        rts

trim_helper_country:
        ldy #23
thc_l:
        lda (reclo),y
        cmp #$20
        bne thc_ok
        dey
        bpl thc_l
        ldy #13
thc_ok:
        iny
        sty count
        rts

; --------------------------------------------------------------
; clear text rows 20..24
; --------------------------------------------------------------
clear_text:
        lda #20
        sta ctrow
ct_loop:
        ldx #0
        ldy ctrow
        jsr gotoxy
        ldy #0
ct_sp:
        lda #$20
        jsr CHROUT
        iny
        cpy #39
        bcc ct_sp
        inc ctrow
        lda ctrow
        cmp #25
        bne ct_loop
        rts

; --------------------------------------------------------------
; print zero-terminated string at ptr
; --------------------------------------------------------------
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

; --------------------------------------------------------------
; gotoxy: X = column, Y = row
; --------------------------------------------------------------
gotoxy:
        lda #0
        clc
        jsr PLOT
        rts

; --------------------------------------------------------------
; print A (0..255) as decimal
; --------------------------------------------------------------
print_dec8:
        ldx #$30
pd1:
        cmp #10
        bcc pd2
        sec
        sbc #10
        inx
        jmp pd1
pd2:
        cpx #$30
        beq pd3
        pha
        txa
        jsr CHROUT
        pla
pd3:
        clc
        adc #$30
        jsr CHROUT
        rts

; --------------------------------------------------------------
; RNG: semi-random byte from CIA timers
; --------------------------------------------------------------
rnd:
        lda $DC04
        eor seed
        clc
        adc $DC05
        sta seed
        rts

; rndn: A = N -> A in 0..N-1   ((rnd * N) >> 8)
rndn:
        sta mb
        jsr rnd
        sta ma
        jsr mul8
        lda resh
        rts

; --------------------------------------------------------------
; mul8: ma * mb -> res/resh (unsigned 8x8 -> 16)
; --------------------------------------------------------------
mul8:
        lda #0
        sta res
        sta resh
        ldx #8
m_loop:
        asl ma                  ; C = current bit of ma
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

; --------------------------------------------------------------
; div16: dvd/dvdh / dvs/dvsh -> quotient in dvd/dvdh, rem in rem
; --------------------------------------------------------------
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

; --------------------------------------------------------------
; strings and filenames
; --------------------------------------------------------------
msg_title:
        !text "**** WORLDCITIES ****", $0D, $0D
        !text "10 CITIES WILL BE MARKED ON THE MAP.", $0D
        !text "PICK THE CORRECT CITY NAME FROM", $0D
        !text "THREE OPTIONS USING KEYS 1-3.", $0D, $0D
        !text "NEEDS FILES: CHARMAP, COLMAP, CITIES ON DEVICE 8", $0D, $0D
        !text "PRESS SPACE TO START", $0D, 0
msg_q:
        !text "WHICH CITY IS MARKED ON THE MAP?", 0
msg_correct:
        !text "CORRECT! IT IS ", 0
msg_wrong:
        !text "NO. IT IS ", 0
msg_over:
        !text "GAME OVER", 0
msg_score:
        !text "YOUR SCORE: ", 0
msg_ferr:
        !text "FILE ERROR - CHECK DISK. SPACE=RETRY", 0
msg_few:
        !text "NEED AT LEAST 10 CITIES. SPACE=RETRY", 0

fn_charmap:
        !text "CHARMAP"
fn_colmap:
        !text "COLMAP"
fn_cities:
        !text "CITIES"
