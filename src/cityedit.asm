; ==============================================================
; CITYEDIT - editor for the WORLDCITIES city data file
;
; Edits "CITIES" on device 8: fixed-width records, 40 bytes each:
;   city    = cols  0..12  (13 chars, space padded)
;   ","            col 13
;   country = cols 14..23  (10 chars, space padded)
;   ","            col 24
;   lat     = cols 25..30  ( 6 chars, signed, e.g. -55.68)
;   ","            col 31
;   lon     = cols 32..38  ( 7 chars, e.g. +123.45)
;   CR       col 39  ($0D)
;
; Assemble: acme --cpu 6510 src/cityedit.asm
; ==============================================================

!to "cityedit.prg", cbm
!cpu 6510

; ---------------- KERNAL ----------------
CHROUT  = $FFD2
GETIN   = $FFE4
PLOT    = $FFF0
LOAD    = $FFD5
SAVE    = $FFD8
SETNAM  = $FFBD
SETLFS  = $FE00
READST  = $FFB7
CLOSE   = $FFC3
CLRCHN  = $FFCC

; ---------------- memory ----------------
CITYBUF = $6000
LINBUF  = $7000
RECLEN  = 40
RECMAX  = 160
NUMROWS = 20             ; rows shown per page

; ---------------- zero page ----------------
reclo   = $FB
rechi   = $FC
srco    = $FD
srch    = $FE
ptr     = $02

; ---------------- variables ----------------
seed    = $33C
numrec  = $33E
cursor  = $33F
top     = $340
curslot = $341
editcol = $342
editlen = $343
editfield = $344
tmpx    = $345
count   = $346
ctrow   = $347
numlo   = $348
numhi   = $349
negf    = $34A
tmpd    = $34B
tlo     = $34C
thi     = $34D
ma      = $34E
mb      = $34F
res     = $350
resh    = $351

; field definitions: offset, length, separator column
FLD_CITY    = 0
FLD_CITY_L  = 13
FLD_COUNTRY = 14
FLD_COUNTRY_L = 10
FLD_LAT     = 25
FLD_LAT_L   = 6
FLD_LON     = 32
FLD_LON_L   = 7

; ==============================================================
*=$0801
        !byte $0B,$08,$0A,$00,$9E,$32,$30,$36,$32,$00,$00,$00
*=$080D

main:
        lda #0
        sta $D020
        sta $D021
        lda #$93
        jsr CHROUT

        lda $DC04
        sta seed
        lda $DC05
        eor seed
        sta seed

        lda #<msg_title
        sta ptr
        lda #>msg_title
        sta ptr+1
        jsr print_str

wait_start:
        jsr GETIN
        cmp #$20
        bne wait_start

        jsr load_cities

mainloop:
        jsr clear_screen
        jsr draw_header
        jsr draw_list
        jsr draw_status
        jsr draw_cursor
        jsr get_cmd
        jmp mainloop

; --------------------------------------------------------------
; load CITIES (raw, no load address)
; --------------------------------------------------------------
load_cities:
        lda #6
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
        bcs lc_start_fresh
        jsr close_ch
        lda #<CITYBUF
        sta ptr
        lda #>CITYBUF
        sta ptr+1
        ldx #0
lcc_loop:
        ldy #0
        lda (ptr),y
        beq lcc_done
        inx
        clc
        lda ptr
        adc #RECLEN
        sta ptr
        lda ptr+1
        adc #0
        sta ptr+1
        cpx #RECMAX
        beq lcc_done
        jmp lcc_loop
lcc_done:
        stx numrec
        rts
lc_start_fresh:
        jsr close_ch
        lda #0
        sta numrec
        ldx #0
lsf_loop:
        txa
        pha
        ldx #0
lsf_zero:
        lda #0
        sta CITYBUF,x
        sta CITYBUF+$0100,x
        sta CITYBUF+$0200,x
        sta CITYBUF+$0300,x
        sta CITYBUF+$0400,x
        sta CITYBUF+$0500,x
        sta CITYBUF+$0600,x
        sta CITYBUF+$0700,x
        inx
        bne lsf_zero
        pla
        tax
        inx
        cpx #8
        bne lsf_loop
        rts

; --------------------------------------------------------------
; save CITIES
; --------------------------------------------------------------
k_save:
        lda numrec
        beq msg_empty
        lda numrec
        sta res
        lda #0
        sta resh
lsb_loop:
        lda res
        clc
        adc #0
        bne lsb_calc
lsb_calc:
        lda numrec
        sta ma
        lda #RECLEN
        sta mb
        jsr mul8                ; res = numrec * 40
        lda res
        clc
        adc #<CITYBUF
        sta srto
        lda resh
        adc #>CITYBUF
        sta srto+1
        lda numrec
        sta ma
        lda #0
        sta mb
        jsr mul8
        lda res
        clc
        adc #0
        sta res2
        jmp do_save
srto    = $352
srth    = $353
res2    = $354

do_save:
        lda #6
        ldx #<fn_cities
        ldy #>fn_cities
        jsr SETNAM
        lda #2
        ldx #8
        ldy #2
        jsr SETLFS
        lda #<CITYBUF
        ldx #<CITYBUF
        ldy #>CITYBUF
        jsr SAVE
        jsr close_ch
        lda #<msg_saved
        sta ptr
        lda #>msg_saved
        sta ptr+1
        jsr print_str
        jmp k_done

; --------------------------------------------------------------
; commands: U/D move, A add, D del, E edit, S save, Q quit/reload
; (get_cmd receives key in A)
; --------------------------------------------------------------
get_cmd:
        jsr GETIN
        beq get_cmd
        cmp #$11                ; cursor down
        bne gc1
        ldy cursor
        cpy numrec
        bcs gc_rts
        cpy numrec
        beq gc_rts
        iny
        cpy numrec
        bcc gc_dn
        rts
gc_dn:
        sty cursor
        jsr scroll_check
        rts
gc1:
        cmp #$91                ; cursor up
        bne gc2
        ldy cursor
        beq gc_rts
        dey
        sty cursor
        jsr scroll_check
        rts
gc2:
        cmp #$41                ; "A" add record
        bne gc3
        jmp k_add
gc3:
        cmp #$45                ; "E" edit record
        bne gc4
        jmp k_edit
gc4:
        cmp #$44                ; "D" delete record
        bne gc5
        jmp k_del
gc5:
        cmp #$53                ; "S" save
        bne gc6
        jmp k_save
gc6:
        cmp #$52                ; "R" reload
        bne gc7
        jmp k_reload
gc7:
        cmp #$51                ; "Q" quit
        bne gc_rts
        jmp main
gc_rts:
        rts

msg_empty:
        lda #<msg_none
        sta ptr
        lda #>msg_none
        sta ptr+1
        jsr print_str
k_done:
        jsr wait_space
        rts

k_reload:
        jsr load_cities
        lda #0
        sta cursor
        sta top
        rts

; --------------------------------------------------------------
; A: append a blank record at end, then edit it
; --------------------------------------------------------------
k_add:
        lda numrec
        cmp #RECMAX
        bcc ka_ok
        lda #<msg_full
        sta ptr
        lda #>msg_full
        sta ptr+1
        jsr print_str
        jsr wait_space
        rts
ka_ok:
        lda #<CITYBUF
        sta reclo
        lda #>CITYBUF
        sta rechi
        ldx numrec
        beq ka_set
ka_loop:
        clc
        lda reclo
        adc #RECLEN
        sta reclo
        lda rechi
        adc #0
        sta rechi
        dex
        bne ka_loop
ka_set:
        ldy #0
ka_fill:
        lda #$20
        sta (reclo),y
        iny
        cpy #39
        bcc ka_fill
        lda #$0D
        ldy #39
        sta (reclo),y
        ldy #13
        lda #$2C
        sta (reclo),y
        ldy #24
        lda #$2C
        sta (reclo),y
        ldy #31
        lda #$2C
        sta (reclo),y
        inc numrec
        lda numrec
        sta curslot             ; will be adjusted below
        lda numrec
        sec
        sbc #1
        sta cursor
        jsr scroll_check
        lda cursor
        jmp k_edit

; --------------------------------------------------------------
; D: delete record at cursor (move following records up)
; --------------------------------------------------------------
k_del:
        lda numrec
        beq msg_empty
        lda cursor
        cmp numrec
        bcc kd_ok
        jmp msg_empty
kd_ok:
        lda #<CITYBUF
        clc
        adc cursor
        sta reclo
        lda #0
        sta rechi
        lda rechi
        cmp #0
        beq kd_mul              ; rechi needs numrec*40/256 handled below
kd_mul:
        lda #<CITYBUF
        sta reclo
        lda #>CITYBUF
        sta rechi
        ldx cursor
        beq kd_set
kd_ml:
        clc
        lda reclo
        adc #RECLEN
        sta reclo
        lda rechi
        adc #0
        sta rechi
        dex
        bne kd_ml
kd_set:
        lda numrec
        sec
        sbc cursor
        sta count               ; records to move
        beq kd_zero
        ldx #0
kd_move:
        stx tmpx
        ; copy record (cursor + x + 1) to (cursor + x)
        lda reclo
        clc
        adc #RECLEN
        sta srco
        lda rechi
        adc #0
        sta srch
        ldy #0
kd_c1:
        lda (srco),y
        sta (reclo),y
        iny
        cpy #RECLEN
        bcc kd_c1
        lda reclo
        clc
        adc #RECLEN
        sta reclo
        lda rechi
        adc #0
        sta rechi
        lda srto
        sta srco
        lda srto+1
        sta srch
        ldx tmpx
        inx
        cpx count
        bcc kd_move
kd_zero:
        dec numrec
        lda cursor
        cmp numrec
        bcc kd_cur
        lda numrec
        sta cursor
kd_cur:
        jsr scroll_check
        rts

; --------------------------------------------------------------
; E: edit record at cursor, field by field
; --------------------------------------------------------------
k_edit:
        lda numrec
        beq msg_empty
        lda cursor
        cmp numrec
        bcc ke_ok
        jmp msg_empty
ke_ok:
        lda cursor
        jsr get_recptr
        lda #FLD_CITY
        sta editfield
ke_loop:
        jsr draw_edit
        jsr edit_field
        lda editfield
        cmp #FLD_LON
        beq ke_done
        clc
        lda editfield
        adc #6
        cmp #FLD_LON
        bcc ke_adv
        lda #FLD_LON
ke_adv:
        sta editfield
        jmp ke_loop
ke_done:
        lda #0
        sta curslot
        jsr draw_edit_done
        rts

; --------------------------------------------------------------
; get_recptr: A = record index -> reclo/rechi
; --------------------------------------------------------------
get_recptr:
        sta tmpx
        lda #<CITYBUF
        sta reclo
        lda #>CITYBUF
        sta rechi
        ldx tmpx
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
; edit one field: use LINBUF, RETURN accepts
; --------------------------------------------------------------
edit_field:
        lda editfield
        asl a                    ; *2 not used, just placeholder
        lda editfield
        cmp #FLD_CITY
        bne ef_c1
        lda #FLD_CITY_L
        jmp ef_set
ef_c1:
        cmp #FLD_COUNTRY
        bne ef_c2
        lda #FLD_COUNTRY_L
        jmp ef_set
ef_c2:
        cmp #FLD_LAT
        bne ef_c3
        lda #FLD_LAT_L
        jmp ef_set
ef_c3:
        lda #FLD_LON_L
ef_set:
        sta editlen

        ; copy field to LINBUF
        lda editfield
        clc
        adc #0
        sta srco
        lda #0
        sta srch
        ldy #0
ef_copy:
        lda (reclo),y
        sta LINBUF,y
        iny
        cpy editlen
        bcc ef_copy
        lda #0
        sta LINBUF,y            ; terminate
        lda #0
        sta editcol

ef_key:
        jsr GETIN
        beq ef_key
        cmp #$0D                ; RETURN: accept
        beq ef_accept
        cmp #$14                ; DELETE
        beq ef_del
        cmp #$20                ; space or printable?
        bcc ef_key
        cmp #$7F
        bcs ef_key
        ldy editcol
        cpy editlen
        bcs ef_key
        sta LINBUF,y
        sta ef_show
        jsr draw_edit
        inc editcol
        jmp ef_key
ef_del:
        lda editcol
        beq ef_key
        dec editcol
        ldy editcol
        lda #$20
        sta LINBUF,y
        sta ef_show
        jsr draw_edit
        jmp ef_key
ef_show = $355

ef_accept:
        ; write LINBUF back into the record field
        ldy #0
ef_write:
        lda LINBUF,y
        ldy editfield
        ldx editfield
        ldy #0
ef_w1:
        cpx editfield
        bne ef_w2
        ldy #0
        jmp ef_w3
ef_w2:
        ldy #0
ef_w3:
        ldy #0
        ldx #0
ef_w4:
        txa
        clc
        adc editfield
        tay
        lda LINBUF,x
        sta (reclo),y
        inx
        cpx editlen
        bcc ef_w4
        rts

; --------------------------------------------------------------
; drawing
; --------------------------------------------------------------
clear_screen:
        lda #$93
        jsr CHROUT
        rts

draw_header:
        ldx #0
        ldy #0
        jsr gotoxy
        lda #<msg_head
        sta ptr
        lda #>msg_head
        sta ptr+1
        jsr print_str
        ldx #0
        ldy #1
        jsr gotoxy
        lda #<msg_head2
        sta ptr
        lda #>msg_head2
        sta ptr+1
        jsr print_str
        rts

draw_list:
        lda #0
        sta ctrow
dl_loop:
        lda top
        clc
        adc ctrow
        cmp numrec
        bcc dl_show
        ; empty row
        ldx #0
        lda ctrow
        clc
        adc #2
        tay
        jsr gotoxy
        jmp dl_next
dl_show:
        sta tmpx
        ldx #0
        lda ctrow
        clc
        adc #2
        tay
        jsr gotoxy
        lda tmpx
        cmp #10
        bcc dl1
        cmp #100
        bcc dl2
        jmp dl3
dl1:
        lda #$30
        jsr CHROUT
        lda #$20
        jsr CHROUT
        lda tmpx
        jmp dl_num
dl2:
        lda #$20
        jsr CHROUT
        jmp dl_num
dl3:
dl_num:
        clc
        adc #$30
        jsr CHROUT
        lda #$20
        jsr CHROUT
        lda #$20
        jsr CHROUT
        lda tmpx
        jsr get_recptr
        jsr print_city
        lda #$20
        jsr CHROUT
        lda #$20
        jsr CHROUT
        jsr print_country
        lda #$20
        jsr CHROUT
        jsr print_lat
        lda #$20
        jsr CHROUT
        jsr print_lon
dl_next:
        inc ctrow
        lda ctrow
        cmp #NUMROWS
        bne dl_loop
        rts

draw_status:
        ldx #0
        ldy #23
        jsr gotoxy
        lda #<msg_stat
        sta ptr
        lda #>msg_stat
        sta ptr+1
        jsr print_str
        lda numrec
        jsr print_dec8
        lda #$20
        jsr CHROUT
        lda #<msg_stat2
        sta ptr
        lda #>msg_stat2
        sta ptr+1
        jsr print_str
        rts

draw_cursor:
        lda cursor
        sec
        sbc top
        sta curslot
        lda curslot
        cmp #NUMROWS
        bcc dc_ok
        lda #0
        sta curslot
dc_ok:
        ldx #0
        lda curslot
        clc
        adc #2
        tay
        jsr gotoxy
        lda #$3E                ; ">"
        jsr CHROUT
        rts

scroll_check:
        lda cursor
        cmp top
        bcc sc_up
        sec
        sbc #NUMROWS-1
        cmp top
        bcc sc_ok
        sta top
        rts
sc_up:
        lda cursor
        sta top
sc_ok:
        rts

; --------------------------------------------------------------
; edit screens
; --------------------------------------------------------------
draw_edit:
        lda #$93
        jsr CHROUT
        lda #<msg_ed1
        sta ptr
        lda #>msg_ed1
        sta ptr+1
        jsr print_str
        ldx #0
        ldy #3
        jsr gotoxy
        lda #<msg_ed_city
        sta ptr
        lda #>msg_ed_city
        sta ptr+1
        jsr print_str
        ldx #0
        ldy #4
        jsr gotoxy
        lda #<msg_ed_country
        sta ptr
        lda #>msg_ed_country
        sta ptr+1
        jsr print_str
        ldx #0
        ldy #5
        jsr gotoxy
        lda #<msg_ed_lat
        sta ptr
        lda #>msg_ed_lat
        sta ptr+1
        jsr print_str
        ldx #0
        ldy #6
        jsr gotoxy
        lda #<msg_ed_lon
        sta ptr
        lda #>msg_ed_lon
        sta ptr+1
        jsr print_str
        ldx #0
        ldy #9
        jsr gotoxy
        lda #<msg_ed_hint
        sta ptr
        lda #>msg_ed_hint
        sta ptr+1
        jsr print_str
        rts

draw_edit_done:
        lda #$93
        jsr CHROUT
        lda #<msg_eddone
        sta ptr
        lda #>msg_eddone
        sta ptr+1
        jsr print_str
        jsr wait_space
        rts

; --------------------------------------------------------------
; print helpers (record at reclo/rechi)
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

print_lat:
        jsr trim_helper_lat
        ldy #25
pl_l:
        lda (reclo),y
        jsr CHROUT
        iny
        cpy count
        bcc pl_l
        rts

print_lon:
        jsr trim_helper_lon
        ldy #32
plo_l:
        lda (reclo),y
        jsr CHROUT
        iny
        cpy count
        bcc plo_l
        rts

trim_helper:
        ldy #12
th_l:
        lda (reclo),y
        cmp #$20
        bne th_ok
        dey
        bpl th_l
        ldy #$FF
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
        cpy #13
        bcs thc_l
        ldy #13
thc_ok:
        iny
        sty count
        rts

trim_helper_lat:
        ldy #30
thl_l:
        lda (reclo),y
        cmp #$20
        bne thl_ok
        dey
        cpy #24
        bcs thl_l
        ldy #24
thl_ok:
        iny
        sty count
        rts

trim_helper_lon:
        ldy #38
tho_l:
        lda (reclo),y
        cmp #$20
        bne tho_ok
        dey
        cpy #31
        bcs tho_l
        ldy #31
tho_ok:
        iny
        sty count
        rts

; --------------------------------------------------------------
; misc
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

gotoxy:
        lda #0
        clc
        jsr PLOT
        rts

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

wait_space:
ws_l:
        jsr GETIN
        cmp #$20
        bne ws_l
        rts

close_ch:
        lda #2
        jsr CLOSE
        jsr CLRCHN
        rts

; --------------------------------------------------------------
; mul8: ma * mb -> res/resh
; --------------------------------------------------------------
mul8:
        lda #0
        sta res
        sta resh
        ldx #8
m_loop:
        asl ma
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
; strings and filenames
; --------------------------------------------------------------
msg_title:
        !text "*** CITYEDIT ***", $0D, $0D
        !text "EDITOR FOR THE WORLDCITIES CITIES FILE.", $0D
        !text "RECORDS: CITY, COUNTRY, LAT, LON.", $0D, $0D
        !text "PRESS SPACE TO START", $0D, 0
msg_head:
        !text "CITYEDIT            RECORDS: ", 0
msg_head2:
        !text "NO  CITY          COUNTRY     LAT     LON", 0
msg_stat:
        !text "RECORDS: ", 0
msg_stat2:
        !text " A=ADD D=DEL E=EDIT S=SAVE R=RELOAD Q=QUIT", 0
msg_none:
        !text "NO RECORDS", $0D, 0
msg_full:
        !text "FILE FULL", $0D, 0
msg_saved:
        !text "SAVED", $0D, 0
msg_ed1:
        !text "EDIT RECORD", $0D, 0
msg_ed_city:
        !text "CITY   : ", 0
msg_ed_country:
        !text "COUNTRY: ", 0
msg_ed_lat:
        !text "LAT    : ", 0
msg_ed_lon:
        !text "LON    : ", 0
msg_ed_hint:
        !text "TYPE, RETURN=NEXT FIELD", 0
msg_eddone:
        !text "EDIT DONE - SPACE=BACK TO LIST", $0D, 0

fn_cities:
        !text "CITIES"
