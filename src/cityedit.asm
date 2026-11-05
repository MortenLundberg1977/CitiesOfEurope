// ==============================================================
// CITYEDIT - editor for the WORLDCITIES "CITIES" data file
//
// Record format (49 bytes):
//   city    cols  0..15   (16 chars, space padded)
//   ","     col 16
//   country cols 17..32   (16 chars, space padded)
//   ","     col 33
//   lat     cols 34..39   ( 6 chars, e.g. -55.68 or +12.34)
//   ","     col 40
//   lon     cols 41..47   ( 7 chars, e.g. +123.45)
//   CR $0D  col 48
// The file ends with a 0 byte. It is a PRG that loads to $6000.
//
// Assemble with build.bat (or: java -jar KickAss.jar src/cityedit.asm -odir ../build)
// ==============================================================

.encoding "petscii_upper"

// ---------------- KERNAL ----------------
.label CHROUT = $FFD2
.label GETIN = $FFE4
.label PLOT = $FFF0
.label LOAD = $FFD5
.label SAVE = $FFD8
.label SETNAM = $FFBD
.label SETLFS = $FFBA
.label CLOSE = $FFC3
.label CLRCHN = $FFCC

// ---------------- memory ----------------
.label CITYBUF = $6000
.label LINBUF = $C000          // field being edited
.const RECLEN = 49
.const RECMAX = 250            // same limit as the game
.const NUMROWS = 20            // list rows on screen (rows 2..21)

// ---------------- zero page ----------------
.label reclo = $FB             // record pointer
.label rechi = $FC
.label srco = $FD              // copy source / SAVE start pointer
.label srch = $FE
.label ptr = $02

// ---------------- variables ----------------
.label numrec = $33E
.label cursor = $33F
.label top = $340
.label editcol = $342
.label editlen = $343
.label editfield = $344        // field offset (0, 17, 34, 41)
.label fldcur = $345           // which field is being edited (0..3)
.label tmpa = $346
.label count = $347
.label ctrow = $348
.label endlo = $34D            // SAVE end address
.label endh = $34E
.label gxcol = $34F
.label pdh = $350              // print_dec8 hundreds digit

BasicUpstart2(main)

main:
        lda #0
        sta $D020
        sta $D021
        lda #1
        sta $0286               // white text
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

// --------------------------------------------------------------
// load CITIES. Missing file -> empty database.
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
        bcs lc_fresh
        jsr close_ch
        jmp lc_count
lc_fresh:
        jsr close_ch
        lda #0
        sta numrec
        sta CITYBUF
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

// --------------------------------------------------------------
// S: save CITIES, replacing the file on disk
// --------------------------------------------------------------
k_save:
        lda numrec
        bne ks_go
        jmp ks_empty
ks_go:
        jsr get_recptr          // reclo = end of the last record
        lda #0
        tay
        sta (reclo),y           // end marker
        clc
        lda reclo
        adc #1                  // SAVE end address is one past the last byte
        sta endlo
        lda rechi
        adc #0
        sta endh
        lda #fn_end-fn_save
        ldx #<fn_save
        ldy #>fn_save
        jsr SETNAM
        lda #2
        ldx #8
        ldy #1
        jsr SETLFS
        lda #<CITYBUF
        sta srco
        lda #>CITYBUF
        sta srch
        lda #srco               // A = zero-page pointer to the start address
        ldx endlo
        ldy endh
        jsr SAVE
        php
        jsr close_ch
        jsr status_line
        plp
        bcc ks_ok
        lda #<msg_ferr
        sta ptr
        lda #>msg_ferr
        sta ptr+1
        jsr print_str
        jmp wait_space
ks_ok:
        lda #<msg_saved
        sta ptr
        lda #>msg_saved
        sta ptr+1
        jsr print_str
        jmp wait_space
ks_empty:
        jsr status_line
        lda #<msg_none
        sta ptr
        lda #>msg_none
        sta ptr+1
        jsr print_str
        jmp wait_space

// --------------------------------------------------------------
// command keys
// --------------------------------------------------------------
get_cmd:
        jsr GETIN
        beq get_cmd
        cmp #$11                // down
        bne gc1
        ldy cursor
        iny
        cpy numrec
        bcs gc_rts
        sty cursor
        jmp scroll_check
gc1:
        cmp #$91                // up
        bne gc2
        ldy cursor
        beq gc_rts
        dey
        sty cursor
        jmp scroll_check
gc2:
        cmp #$41                // A add
        bne gc3
        jmp k_add
gc3:
        cmp #$45                // E edit
        bne gc4
        jmp k_edit
gc4:
        cmp #$44                // D delete
        bne gc5
        jmp k_del
gc5:
        cmp #$53                // S save
        bne gc6
        jmp k_save
gc6:
        cmp #$52                // R reload
        bne gc7
        jsr load_cities
        lda #0
        sta cursor
        sta top
        rts
gc7:
        cmp #$51                // Q quit
        bne gc_rts
        pla                     // drop get_cmd's return address
        pla
        jmp main
gc_rts:
        rts

// --------------------------------------------------------------
// A: append a blank record, edit it
// --------------------------------------------------------------
k_add:
        lda numrec
        cmp #RECMAX
        bcc ka_ok
        jsr status_line
        lda #<msg_full
        sta ptr
        lda #>msg_full
        sta ptr+1
        jsr print_str
        jmp wait_space
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

// fill record at reclo/rechi with blanks + commas + CR
blank_record:
        ldy #0
        lda #$20
br_loop:
        sta (reclo),y
        iny
        cpy #RECLEN-1
        bcc br_loop
        lda #$2C
        ldy #16
        sta (reclo),y
        ldy #33
        sta (reclo),y
        ldy #40
        sta (reclo),y
        ldy #RECLEN-1
        lda #$0D
        sta (reclo),y
        rts

// --------------------------------------------------------------
// D: delete record at cursor, move the rest down
// --------------------------------------------------------------
k_del:
        lda numrec
        bne kd_ok
        jsr status_line
        lda #<msg_none
        sta ptr
        lda #>msg_none
        sta ptr+1
        jsr print_str
        jmp wait_space
kd_ok:
        lda cursor
        sta tmpa                // tmpa = record being overwritten
kd_loop:
        lda tmpa
        clc
        adc #1
        cmp numrec
        bcs kd_last
        jsr get_recptr          // source = next record
        lda reclo
        sta srco
        lda rechi
        sta srch
        lda tmpa
        jsr get_recptr          // dest
        ldy #0
kd_copy:
        lda (srco),y
        sta (reclo),y
        iny
        cpy #RECLEN
        bcc kd_copy
        inc tmpa
        jmp kd_loop
kd_last:
        dec numrec
        lda numrec
        jsr get_recptr
        lda #0
        tay
        sta (reclo),y           // new end marker
        lda cursor
        cmp numrec
        bcc kd_cur
        lda numrec
        beq kd_cur
        sec
        sbc #1
        sta cursor
kd_cur:
        jmp scroll_check

// --------------------------------------------------------------
// E: edit record at cursor, field by field
// --------------------------------------------------------------
k_edit:
        lda numrec
        bne ke_ok
        jsr status_line
        lda #<msg_none
        sta ptr
        lda #>msg_none
        sta ptr+1
        jsr print_str
        jmp wait_space
ke_ok:
        lda #0
        sta fldcur
ke_loop:
        lda cursor
        jsr get_recptr
        jsr edit_field
        inc fldcur
        lda fldcur
        cmp #4
        bne ke_loop
        ldx #0
        ldy #10
        jsr gotoxy
        lda #<msg_eddone
        sta ptr
        lda #>msg_eddone
        sta ptr+1
        jsr print_str
        jmp wait_space

// --------------------------------------------------------------
// edit_field: edit field fldcur of record at reclo/rechi
// --------------------------------------------------------------
edit_field:
        lda fldcur
        asl
        tax
        lda FLDTBL,x
        sta editfield
        lda FLDTBL+1,x
        sta editlen
        // copy field into LINBUF
        ldx #0
ef_copy:
        txa
        clc
        adc editfield
        tay
        lda (reclo),y
        sta LINBUF,x
        inx
        cpx editlen
        bcc ef_copy
        lda #0
        sta editcol
        jsr draw_edit
ef_key:
        jsr GETIN
        beq ef_key
        cmp #$0D                // RETURN = accept
        beq ef_accept
        cmp #$14                // DELETE
        beq ef_del
        cmp #$20
        bcc ef_key
        cmp #$60                // upper case, digits and signs only
        bcs ef_key
        ldx editcol
        cpx editlen
        bcs ef_key
        sta LINBUF,x
        inc editcol
        jsr draw_edit
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
        // write LINBUF back into the record field
        ldx #0
ef_write:
        txa
        clc
        adc editfield
        tay
        lda LINBUF,x
        sta (reclo),y
        inx
        cpx editlen
        bcc ef_write
        rts

// --------------------------------------------------------------
// get_recptr: A = record index -> reclo/rechi
// --------------------------------------------------------------
get_recptr:
        tax
        lda #<CITYBUF
        sta reclo
        lda #>CITYBUF
        sta rechi
        cpx #0
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
// drawing
// --------------------------------------------------------------
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

// one row per record: number (col 1), city (col 5), country (col 22)
draw_list:
        lda #0
        sta ctrow
dl_loop:
        lda top
        clc
        adc ctrow
        cmp numrec
        bcs dl_next
        sta tmpa
        lda ctrow
        clc
        adc #2
        tay
        ldx #1
        jsr gotoxy
        lda tmpa
        clc
        adc #1                  // show 1-based numbers
        jsr print_dec8
        lda ctrow
        clc
        adc #2
        tay
        ldx #5
        jsr gotoxy
        lda tmpa
        jsr get_recptr
        ldy #0
        jsr print16
        lda ctrow
        clc
        adc #2
        tay
        ldx #22
        jsr gotoxy
        ldy #17
        jsr print16
dl_next:
        inc ctrow
        lda ctrow
        cmp #NUMROWS
        bne dl_loop
        rts

// print 16 chars of the record at reclo, from offset Y
print16:
        lda #16
        sta count
p16_loop:
        lda (reclo),y
        jsr CHROUT
        iny
        dec count
        bne p16_loop
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

// clear row 22 and put the cursor there for a message
status_line:
        ldx #0
        ldy #22
        jsr gotoxy
        ldx #39
        lda #$20
sl_loop:
        jsr CHROUT
        dex
        bne sl_loop
        ldx #0
        ldy #22
        jmp gotoxy

draw_cursor:
        lda numrec
        beq dc_done
        lda cursor
        sec
        sbc top
        clc
        adc #2
        tay
        ldx #0
        jsr gotoxy
        lda #$3E                // ">"
        jsr CHROUT
dc_done:
        rts

scroll_check:
        lda cursor
        cmp top
        bcc sc_up
        sec
        sbc #NUMROWS-1
        bcc sc_ok               // near the top: top can stay
        cmp top
        bcc sc_ok
        beq sc_ok
        sta top
        rts
sc_up:
        lda cursor
        sta top
sc_ok:
        rts

// edit screen: prompt lines + current field content from LINBUF
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
        ldx #0
        ldy #3
        jsr gotoxy
        lda fldcur
        asl
        tax
        lda prompt_tbl,x
        sta ptr
        lda prompt_tbl+1,x
        sta ptr+1
        jsr print_str
        ldx #0
de_sh:
        cpx editcol
        bne de_sh2
        lda #$12                // reverse on: the cursor position
        jsr CHROUT
        lda LINBUF,x
        jsr CHROUT
        lda #$92                // reverse off
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

// --------------------------------------------------------------
// misc
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

gotoxy:                         // X = column, Y = row; KERNAL PLOT wants X = row, Y = column
        stx gxcol
        tya
        tax
        ldy gxcol
        clc
        jsr PLOT
        rts

// print A (0..255) as decimal
print_dec8:
        ldx #0
pd_h:
        cmp #100
        bcc pd_hd
        sbc #100
        inx
        bne pd_h
pd_hd:
        stx pdh
        ldx #0
pd_t:
        cmp #10
        bcc pd_td
        sbc #10
        inx
        bne pd_t
pd_td:
        pha                     // ones
        lda pdh
        beq pd_nohund
        clc
        adc #$30
        jsr CHROUT
        txa
        jmp pd_tens
pd_nohund:
        txa
        beq pd_ones
pd_tens:
        clc
        adc #$30
        jsr CHROUT
pd_ones:
        pla
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

// --------------------------------------------------------------
// tables and strings
// --------------------------------------------------------------
// field table: offset,len
FLDTBL:
        .byte 0,16, 17,16, 34,6, 41,7

prompt_tbl:
        .word msg_ed_city, msg_ed_country, msg_ed_lat, msg_ed_lon

msg_title:
        .text "*** CITYEDIT ***"
        .byte $0D, $0D
        .text "EDITOR FOR THE WORLDCITIES CITIES FILE."
        .byte $0D
        .text "EDITS CITIES ON DEVICE 8."
        .byte $0D, $0D
        .text "PRESS SPACE TO START"
        .byte $0D, 0
msg_head:
        .text "CITYEDIT  RECORDS: "
        .byte 0
msg_stat:
        .text "CRSR=MOVE A=ADD D=DEL E=EDIT"
        .byte $0D
        .text "S=SAVE R=RELOAD Q=QUIT"
        .byte 0
msg_none:
        .text "NO RECORDS - SPACE"
        .byte 0
msg_full:
        .text "FILE FULL - SPACE"
        .byte 0
msg_saved:
        .text "SAVED - SPACE"
        .byte 0
msg_ferr:
        .text "DISK ERROR - SPACE"
        .byte 0
msg_ed1:
        .text "EDIT RECORD - RETURN=NEXT FIELD"
        .byte 0
msg_ed_city:
        .text "CITY   : "
        .byte 0
msg_ed_country:
        .text "COUNTRY: "
        .byte 0
msg_ed_lat:
        .text "LAT    : "
        .byte 0
msg_ed_lon:
        .text "LON    : "
        .byte 0
msg_ed_hint:
        .text "TYPE. RETURN=NEXT, DEL=BACKSPACE"
        .byte 0
msg_eddone:
        .text "DONE - SPACE=BACK TO LIST"
        .byte 0

fn_save:
        .text "@0:"
fn_cities:
        .text "CITIES"
fn_end:
