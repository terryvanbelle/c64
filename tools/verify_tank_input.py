#!/usr/bin/env python3
"""Check Ironveil's compiled input decoder with cc65's sim65.

Only the two hardware-access leaf routines are replaced with fixtures. The
ordinary keyboard/button decoder and mode-transition logic execute as 6502
code. This does not check CIA electrical behavior, host keyboard rollover,
graphics, or IRQ timing. Requires ca65, cl65, and sim65; no Python dependencies.
"""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

GLUE = r'''
.setcpu "6502"
.import _hull, _matrix, _raw, _observed_y
.export hull, _poll, _dual_controls, _menu_controls, _menu_difficulty
.export _input_mode, _fire_button_previous, fixture_scan, fixture_ports
hull = _hull
_dual_controls = dual_controls
_menu_controls = menu_controls
_menu_difficulty = menu_difficulty
_input_mode = input_mode
_fire_button_previous = fire_button_previous
.segment "CODE"
_poll:
    ldy #90
    jsr duel_input_poll
    sty _observed_y
    rts
fixture_scan:
    ldx #7
@copy:
    lda _matrix,x
    sta input_matrix,x
    dex
    bpl @copy
    rts
fixture_ports:
    lda _raw
    eor #$ff
    sta $dc00
    lda _raw+1
    eor #$ff
    sta $dc01
    rts
'''

HARNESS = r'''
#include <stdio.h>
#include <string.h>
extern unsigned char dual_controls[2], menu_controls, menu_difficulty;
extern unsigned char input_mode, fire_button_previous[2];
extern void poll(void);
unsigned char hull[2], matrix[8], raw[2], observed_y;
static unsigned checks;
static unsigned char columns[2][5]={{1,1,1,2,2},{3,4,3,4,5}};
static unsigned char rows[2][5]={{2,32,4,4,128},{64,128,16,16,16}};
static void fixture(unsigned char a,unsigned char b){
    unsigned p,i;raw[0]=a;raw[1]=b;memset(matrix,0,8);
    for(p=0;p<2;++p)for(i=0;i<5;++i)
        if(raw[p]&(1u<<i))matrix[columns[p][i]]|=rows[p][i];
}
/* Derive heading from Cartesian signs, independently of the assembly table. */
static unsigned char expected(unsigned char bits,unsigned char h,unsigned char prev,unsigned char mode){
    int dx,dy;unsigned char d,delta,result;
    if(bits&16)return (bits&12)<<3;
    result=prev?16:0;
    if(mode)return result|(bits&15);
    dx=!!(bits&8)-!!(bits&4);dy=!!(bits&2)-!!(bits&1);
    if(!dx&&!dy)return result|((bits&15)?3:0);
    if(!dy)d=dx>0?2:6;
    else if(!dx)d=dy>0?4:0;
    else if(dy<0)d=dx>0?1:7;
    else d=dx>0?3:5;
    delta=(d-h)&7;
    return result|(delta==0?1:delta<=4?8:4);
}
static int check(unsigned char a,unsigned char b,const char *context){
    ++checks;
    if(dual_controls[0]!=a||dual_controls[1]!=b||observed_y!=90){
        printf("FAIL %s controls=%u,%u expected=%u,%u Y=%u\n",context,
               dual_controls[0],dual_controls[1],a,b,observed_y);return 0;
    }
    return 1;
}
int main(void){
    unsigned mode,bits,h,prev,p,i;unsigned char wants[2],old,buttons;
    for(mode=0;mode<2;++mode){
        input_mode=(unsigned char)mode;fixture(0,0);poll();
        for(bits=0;bits<32;++bits)for(h=0;h<8;++h)for(prev=0;prev<4;++prev){
            fixture((unsigned char)bits,(unsigned char)(31-bits));
            hull[0]=(unsigned char)h;hull[1]=(unsigned char)(7-h);
            for(p=0;p<2;++p){
                fire_button_previous[p]=(prev&(1u<<p))?16:0;
                wants[p]=expected(raw[p],hull[p],fire_button_previous[p],(unsigned char)mode);
            }
            menu_difficulty=84;poll();
            if(!check(wants[0],wants[1],"direction/button combinations"))return 1;
            if(menu_controls||menu_difficulty!=84){puts("FAIL menu state");return 1;}
            for(p=0;p<2;++p)if(fire_button_previous[p]!=(raw[p]&16)){
                puts("FAIL button history");return 1;
            }
        }
        fixture(16,16);poll();
        if(!check(0,0,"hold both buttons"))return 1;
        for(i=0;i<64;++i){poll();if(!check(0,0,"held buttons never shoot"))return 1;}
        fixture(20,24);poll();if(!check(32,64,"aim while holding"))return 1;
        fixture(0,0);poll();if(!check(16,16,"one release pulse"))return 1;
        poll();if(!check(0,0,"no repeated release pulse"))return 1;
    }
    /* Removed aim keys never affect the live decoder; 2 remains a menu key. */
    input_mode=0;fixture(0,0);poll();
    matrix[7]|=64|8;matrix[6]|=4;matrix[0]|=2;
    poll();if(!check(0,0,"removed Q/2/semicolon/Return controls"))return 1;
    fixture(0,0);matrix[7]=1;poll();
    if(!check(0,0,"pause without movement")||menu_controls!=1)return 1;
    /* Both directions of a device switch discard the previous device's hold. */
    for(old=0;old<2;++old)for(buttons=0;buttons<4;++buttons){
        input_mode=old;fixture(0,0);poll();
        fixture(16,16);poll();
        input_mode=1-old;fixture((buttons&1)?16:0,(buttons&2)?16:0);poll();
        if(!check(0,0,"mode switch has no stale shot"))return 1;
        fixture(0,0);poll();
        if(!check((buttons&1)?16:0,(buttons&2)?16:0,"new device release"))return 1;
        poll();if(!check(0,0,"new device neutral"))return 1;
    }
    printf("PASS %u compiled input samples: both players, 16 direction chords, "
           "eight hull headings, held/released buttons, mode switches, removed keys, pause and Y ABI.\n",checks);
    return 0;
}
'''


def main():
    source = (ROOT / "src/tanks/input.s").read_text()
    source = source.replace(".import hull\n", "")
    # Keep the complete decoder; replace only electrical reads/writes with
    # deterministic matrices and active-low port samples in the flat-RAM CPU.
    source, count = re.subn(r"\.proc scan_keyboard\n.*?\.endproc",
                            ".proc scan_keyboard\n    jmp fixture_scan\n.endproc",
                            source, flags=re.S)
    assert count == 1
    source, count = re.subn(r"\.proc ports_to_inputs\n.*?\.endproc",
                            ".proc ports_to_inputs\n    jmp fixture_ports\n.endproc",
                            source, flags=re.S)
    assert count == 1
    with tempfile.TemporaryDirectory(prefix="ironveil-input-") as directory:
        work = Path(directory)
        # Glue shares the input assembly translation unit to copy the private
        # matrix fixture without exporting a production-only testing interface.
        (work / "input.s").write_text(source + "\n" + GLUE)
        (work / "harness.c").write_text(HARNESS)
        subprocess.run(["ca65", str(work / "input.s"), "-o", str(work / "input.o")], check=True)
        subprocess.run(["cl65", "-t", "sim6502", "-O", str(work / "harness.c"),
                        str(work / "input.o"), "-o", str(work / "harness")], check=True)
        subprocess.run(["sim65", str(work / "harness")], check=True)


if __name__ == "__main__":
    main()
