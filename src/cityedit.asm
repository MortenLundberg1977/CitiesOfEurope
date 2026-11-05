; ==============================================================
; CITYEDIT - editor for the WORLDCITIES "CITIES" data file
;
; Record format (40 bytes):
;   city    cols  0..12   (13 chars, space padded)
;   ","     col 13
;   country cols 14..23   (10 chars, space padded)
;   ","     col 24
;   lat     cols 25..30   ( 6 chars, e.g. -55.7 or +12.34)
;   ","     col 31
;   lon     cols 32..38   ( 7 chars, e.g. +123.45)
;   CR $0D  col 39
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
CLOSE   = $FFC3
CLRCHN  = $FFCC

; ---------------- memory ----------------
CITYBUF = $6000
LINBUF  = $7000
RECLEN  = 40
RECMAX  = 160
NUMROWS = 20             ; list rows on screen (rows 2..21)

; ---------------- zero page ----------------
reclo   = $FB            ; record pointer
rechi   = $FC
srco    = $FD           ; copy source
srch    = $FE
dsto    = $FB           ; copy dest (aliases reclo, used at other times)
dsth    = $FC
ptr     = $02
endlo   = $BB            ; KERNAL SAVE end address low

; ---------------- variables ----------------
seed    = $33C
numrec  = $33E
cursor  = $33F
top     = $340
editcol = $342
editlen = $343
editfield = $344         ; field offset (0, 14, 25, 32)
fldcur  = $345           ; which field is being edited (0..3)
tmpa    = $346
count   = $347
ctrow   = $348
ma      = $349
mb      = $34A
res     = $34B
resh    = $34C
endh    = $34D

; field table: offset,len
FLDTBL:
        !byte 0,13, 14,10, 25,6, 32,7

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
        lda #0
        sta cursor
        sta top

mainloop:
        jsr clear_screen
        jsr draw_header
        jsr draw_list
        jsr draw_status
        jsr draw_cursor
        jsr get_cmd
        jmp mainloop

; --------------------------------------------------------------
; load CITIES (raw). Missing file -> empty database.
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
        bcs lc_fresh
        jsr close_ch
        jmp lc_count
lc_fresh:
        jsr close_ch
        lda #0
        sta numrec
        jsr clear_buf
        rts
lc_count:
        lda #<CITYBUF
        sta ptr
        lda #>CITYBUF
        sta ptr+1
        ldx #0
        ldy #0
lcc_loop:
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

; clear whole 8 KB buffer
clear_buf:
        ldx #0
cb_loop:
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
        bne cb_loop
        rts

; --------------------------------------------------------------
; save CITIES (raw, SA=2)
; --------------------------------------------------------------
k_save:
        lda numrec
        beq ks_empty
        sta ma
        lda #RECLEN
        sta mb
        jsr mul8                ; res/resh = numrec * 40
        clc
        lda res
        adc #<CITYBUF
        sta endlo
        lda resh
        adc #>CITYBUF
        sta endh
        lda #6
        ldx #<fn_cities
        ldy #>fn_cities
        jsr SETNAM
        lda #2
        ldx #8
        ldy #2
        jsr SETLFS
        lda #<CITYBUF
        ldx #>CITYBUF
        ldy endh
        jsr SAVE
        jsr close_ch
        bcc ks_ok
        lda #<msg_ferr
        sta ptr
        lda #>msg_ferr
        sta ptr+1
        jsr print_str
        jmp ks_done
ks_ok:
        lda #<msg_saved
        sta ptr
        lda #>msg_saved
        sta ptr+1
        jsr print_str
ks_done:
        jsr wait_space
        rts
ks_empty:
        lda #<msg_none
        sta ptr
        lda #>msg_none
        sta ptr+1
        jsr print_str
        jsr wait_space
        rts

; --------------------------------------------------------------
; command keys
; --------------------------------------------------------------
get_cmd:
        jsr GETIN
        beq get_cmd
        cmp #$11                ; down
        bne gc1
        ldy cursor
        cpy numrec
        bcs gc_rts
        iny
        sty cursor
        jsr scroll_check
        rts
gc1:
        cmp #$91                ; up
        bne gc2
        ldy cursor
        beq gc_rts
        dey
        sty cursor
        jsr scroll_check
        rts
gc2:
        cmp #$41                ; A add
        bne gc3
        jmp k_add
gc3:
        cmp #$45                ; E edit
        bne gc4
        jmp k_edit
gc4:
        cmp #$44                ; D delete
        bne gc5
        jmp k_del
gc5:
        cmp #$53                ; S save
        bne gc6
        jmp k_save
gc6:
        cmp #$52                ; R reload
        bne gc7
        jsr load_cities
        lda #0
        sta cursor
        sta top
        rts
gc7:
        cmp #$51                ; Q quit
        bne gc_rts
        jmp main
gc_rts:
        rts

; --------------------------------------------------------------
; A: append a blank record, edit it
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
        lda numrec
        jsr get_recptr
        jsr blank_record
        inc numrec
        lda numrec
        sec
        sbc #1
        sta cursor
        jsr scroll_check
        jmp k_edit

; fill record at reclo/rechi with blanks + commas + CR
blank_record:
        ldy #0
br_loop:
        lda #$20
        sta (reclo),y
        iny
        cpy #39
        bcc br_loop
        ldy #13
        lda #$2C
        sta (reclo),y
        ldy #24
        sta (reclo),y
        ldy #31
        sta (reclo),y
        ldy #39
        lda #$0D
        sta (reclo),y
        rts

; --------------------------------------------------------------
; D: delete record at cursor, move rest down, zero last
; --------------------------------------------------------------
k_del:
        lda numrec
        beq kd_empty
        lda cursor
        cmp numrec
        bcc kd_ok
kd_empty:
        lda #<msg_none
        sta ptr
        lda #>msg_none
        sta ptr+1
        jsr print_str
        jsr wait_space
        rts
kd_ok:
        lda cursor
kd_loop:
        sta tmpa                ; tmpa = current record index
        cmp numrec
        bcs kd_last
        clc
        adc #1                  ; next record
        sta tmpa
        lda tmpa
        jsr get_recptr
        lda reclo
        sta srco
        lda rechi
        sta srch
        lda tmpa
        sec
        sbc #1
        sta tmpa
        jsr get_recptr          ; reclo now = dest
        ldy #0
kd_copy:
        lda (srco),y
        sta (reclo),y
        iny
        cpy #RECLEN
        bcc kd_copy
        lda tmpa
        jmp kd_loop
kd_last:
        dec numrec
        lda numrec
        jsr get_recptr
        ldy #0
kd_zero:
        lda #0
        sta (reclo),y
        iny
        cpy #RECLEN
        bcc kd_zero
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
        beq ke_empty
        lda cursor
        cmp numrec
        bcc ke_ok
ke_empty:
        lda #<msg_none
        sta ptr
        lda #>msg_none
        sta ptr+1
        jsr print_str
        jsr wait_space
        rts
ke_ok:
        lda cursor
        jsr get_recptr
        lda #0
        sta fldcur
ke_loop:
        jsr draw_edit
        jsr edit_field
        lda fldcur
        cmp #3
        beq ke_done
        inc fldcur
        jmp ke_loop
ke_done:
        lda #<msg_eddone
        sta ptr
        lda #>msg_eddone
        sta ptr+1
        jsr print_str
        jsr wait_space
        rts

; --------------------------------------------------------------
; edit_field: edit field fldcur of record at reclo/rechi
; --------------------------------------------------------------
edit_field:
        ldx fldcur
        lda FLDTBL,x
        sta editfield
        inx
        lda FLDTBL,x
        sta editlen
        lda #0
        sta editcol
        ; copy field into LINBUF
        ldy #0
ef_copy:
        ldx editfield
        txa
        clc
        adc #0
        tax
        lda (reclo),y            ; y counts 0..len-1, x unused here
        jmp ef_c2
ef_c2:
        ldx editfield
        lda editcol              ; save
        pha
        lda #0
        sta editcol
ef_c3:
        lda editfield
        clc
        adc editcol
        tay
        lda (reclo),y
        ldx editcol
        sta LINBUF,x
        inc editcol
        lda editcol
        cmp editlen
        bcc ef_c3
        pla
        sta editcol
        jmp ef_key

ef_key:
        jsr GETIN
        beq ef_key
        cmp #$0D                ; RETURN = accept
        beq ef_accept
        cmp #$14                ; DELETE
        beq ef_del
        cmp #$20
        bcc ef_key
        cmp #$60                ; only upper case graphics range accepted
        bcs ef_key
        ldx editcol
        cpx editlen
        bcs ef_key
        sta LINBUF,x
        jsr draw_edit
        inc editcol
        jmp ef_key
ef_del:
        ldx editcol
        beq ef_key
        dex
        stx editcol
        lda #$20
        sta LINBUF,x
        jsr draw_edit
        jmp ef_key
ef_accept:
        ; write LINBUF back into the record field
        ldx #0
ef_write:
        lda editfield
        clc
        adc #0
        tay
        tya
        clc
        adc #0
        tay
        lda editfield
        clc
        adc #0
        sta tmpa
        ldy #0
ef_w1:
        tya
        clc
        adc editfield
        tay
        lda LINBUF,x
        sta (reclo),y
        inx
        cpx editlen
        bcc ef_w1
        rts

; --------------------------------------------------------------
; get_recptr: A = record index -> reclo/rechi
; --------------------------------------------------------------
get_recptr:
        sta tmpa
        lda #<CITYBUF
        sta reclo
        lda #>CITYBUF
        sta rechi
        ldx tmpa
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
        lda numrec
        jsr print_dec8
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
        jmp dl_next
dl_show:
        sta tmpa
        ldx #0
        lda ctrow
        clc
        adc #2
        tay
        jsr gotoxy
        lda tmpa
        cmp #100
        bcs dl_n3
        lda #$20
        jsr CHROUT
        cmp #10
        bcs dl_n2
        lda #$20
        jsr CHROUT
dl_n2:
        lda tmpa
dl_n3:
        lda tmpa
        jsr print_dec8
        lda #$20
        jsr CHROUT
        lda tmpa
        jsr get_recptr
        jsr print_city
        lda #$20
        jsr CHROUT
        lda #$20
        jsr CHROUT
        jsr print_country
        lda #$20
        jsr CHROUT
        jsr print_field_lat
        lda #$20
        jsr CHROUT
        jsr print_field_lon
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
        rts

draw_cursor:
        lda cursor
        sec
        sbc top
        cmp #NUMROWS
        bcc dc_ok
        lda #0
dc_ok:
        clc
        adc #2
        tay
        ldx #0
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

; edit screen: prompt lines + current field content from LINBUF
draw_edit:
        lda #$93
        jsr CHROUT
        ldx #0
        ldy #1
        jsr gotoxy
        lda #<msg_ed1
        sta ptr
        lda #>msg_ed1
        sta ptr+1
        jsr print_str
        ; prompt for the current field
        lda fldcur
        cmp #0
        bne de1
        lda #<msg_ed_city
        sta ptr
        lda #>msg_ed_city
        sta ptr+1
        jsr print_str
        jmp de_show
de1:
        cmp #1
        bne de2
        lda #<msg_ed_country
        sta ptr
        lda #>msg_ed_country
        sta ptr+1
        jsr print_str
        jmp de_show
de2:
        cmp #2
        bne de3
        lda #<msg_ed_lat
        sta ptr
        lda #>msg_ed_lat
        sta ptr+1
        jsr print_str
        jmp de_show
de3:
        lda #<msg_ed_lon
        sta ptr
        lda #>msg_ed_lon
        sta ptr+1
        jsr print_str
de_show:
        ldx #0
de_sh:
        cpx editcol
        bne de_sh2
        lda #$5B                ; "[" marks cursor
        jsr CHROUT
        jmp de_sh3
de_sh2:
        lda LINBUF,x
        jsr CHROUT
de_sh3:
        inx
        cpx editlen
        bcc de_sh
        ldx #0
        ldy #8
        jsr gotoxy
        lda #<msg_ed_hint
        sta ptr
        lda #>msg_ed_hint
        sta ptr+1
        jsr print_str
        rts

; --------------------------------------------------------------
; field printers (record at reclo/rechi, trailing spaces kept
; simple: print fixed width)
; --------------------------------------------------------------
print_city:
        ldy #0
        lda #13
        sta count
        jmp pf_loop
print_country:
        ldy #14
        lda #10
        sta count
        jmp pf_loop
print_field_lat:
        ldy #25
        lda #6
        sta count
        jmp pf_loop
print_field_lon:
        ldy #32
        lda #7
        sta count
pf_loop:
        lda #0
        sta tmpa
pf_l:
        lda (reclo),y
        jsr CHROUT
        iny
        inc tmpa
        lda tmpa
        cmp count
        bcc pf_l
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
; strings
; --------------------------------------------------------------
msg_title:
        !text "*** CITYEDIT ***", $0D, $0D
        !text "EDITOR FOR THE WORLDCITIES CITIES FILE.", $0D
        !text "EDITS CITIES ON DEVICE 8.", $0D, $0D
        !text "PRESS SPACE TO START", $0D, 0
msg_head:
        !text "CITYEDIT  RECORDS: ", 0
msg_stat:
        !text "CRSR=MOVE A=ADD D=DEL E=EDIT S=SAVE R=RELOAD", 0
msg_none:
        !text "NO RECORDS", $0D, 0
msg_full:
        !text "FILE FULL", $0D, 0
msg_saved:
        !text "SAVED", $0D, 0
msg_ferr:
        !text "DISK ERROR", $0D, 0
msg_ed1:
        !text "EDIT RECORD - RETURN=NEXT FIELD", 0
msg_ed_city:
        !text "CITY   : ", 0
msg_ed_country:
        !text "COUNTRY: ", 0
msg_ed_lat:
        !text "LAT    : ", 0
msg_ed_lon:
        !text "LON    : ", 0
msg_ed_hint:
        !text "TYPE. RETURN=NEXT, DEL=BACKSPACE", 0
msg_eddone:
        !text "DONE - SPACE=BACK TO LIST", $0D, 0

fn_cities:
        !text "CITIES"
