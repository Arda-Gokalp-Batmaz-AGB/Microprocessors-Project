.section .vectors, "ax"
	B _start // reset vector
	B SERVICE_UND // undefined instruction vector
	B SERVICE_SVC // software interrrupt vector
	B SERVICE_ABT_INST // aborted prefetch vector
	B SERVICE_ABT_DATA // aborted data vector
	.word 0 // unused vector
	B SERVICE_IRQ // IRQ interrupt vector
	B SERVICE_FIQ // FIQ interrupt vector
	
// Constants
.equ UART_BASE, 0xFF201000    // JAG UART base address
.equ BUTTONS_BASE, 0xFF200050 // Push Buttons base addres
.equ BRAIN_MODE_MASK, 0b100 // States the Brain mode mask mode of interface
.equ MACHINE_MODE_MASK, 0b1000 // States the Machine mode mask mode of interface
.equ PANEL_DECISION_MASK, 0b10 // States decision mode mask of interface
.equ WRITING_MODE_MASK, 0b1 // States writing mode mask of interface

// Brain's Status mask bits
.equ BRAIN_FOCUSED_STATUS_MASK, 0b1 // States brain's FOCUSED mode
.equ BRAIN_DIFFUSED_STATUS_MASK, 0b10 // States brain's DIFFUSED mode

//Machine's Status mask bits
.equ MACHINE_OPEN_STATUS_MASK, 0b1 // States machine's OPEN mode
.equ MACHINE_CLOSED_STATUS_MASK, 0b10 // States machine's CLOSED mode

//Machine and Brain's control mask bits
.equ BRAIN_RESET_MASK, 0b1 // States brain's FOCUSED mode
.equ MACHINE_RESET_MASK, 0b1


.equ MACHINE_BASE_ADDRESS, 0xFFFFea10  // Holds base data address of Machine
.equ MACHINE_MAX_ADDRESS, 0xFFFFF300 // Max possible data address of Machine
.equ MACHINE_POINTER_ADDRESS, 0xFFFFea00 // Holds the current avaliable data address of Machine
.equ MACHINE_RESET_ADDRESS, 0xFFFFea04 // Control bit address of Machine
.equ MACHINE_STATUS_ADDRESS, 0xFFFFea08 // Status bit address of Machine

.equ BRAIN_BASE_ADDRESS, 0xFFFF0110 // Holds base data address of Brain
.equ BRAIN_MAX_ADDRESS,  0xFFFFe9f0 // Max possible data address of Brain
.equ BRAIN_POINTER_ADDRESS, 0xFFFF0100 // Holds the current avaliable data address of Brain
.equ BRAIN_COUNTER_ADDRESS, 0xFFFF0104 // Holds the data count of Brain
.equ BRAIN_RESET_ADDRESS, 0xFFFF0108 // Control bit address of Brain
.equ BRAIN_STATUS_ADDRESS, 0xFFFF010c //  Status bit address of Brain


.equ MEMORY_RESET_MASK, 0xaaaaaaaa // Used while resetting memory addresses
.org    0x1000    // Start at memory location 1000

.text  
Seven_Segment_Base_Addres: .word 0xFF200020
HEXTABLE: .word 0b00111111,0b00000110,0b01011011,0b01001111,0b01100110,0b01101101,0b01111101,0b00000111,0b01111111,0b01101111
// Code Section
.global _start
_start:
	BL Init_Machine_And_Brain


	// Sets Brain mode FOCUSED at start
	LDR R3, =BRAIN_STATUS_ADDRESS
	LDR R1, =BRAIN_FOCUSED_STATUS_MASK
	STR R1,[R3]
	
	// Sets Brain mode MACHINE at start
	LDR R3, =MACHINE_STATUS_ADDRESS
	LDR R1, =MACHINE_OPEN_STATUS_MASK
	STR R1,[R3]
	
	
	
	LDR R12, =PANEL_DECISION_MASK // Sets Decision bit which R12 to panel mode
	// Writes panel decision string to the JTAG UART
	LDR  R6, =DECISION_PANEL_STRING
	PUSH {R0-R11, LR}
	BL LoadText
	POP {R0-R11, LR}
	

	
	B InitInterrupts

// Initialises pointers of Machine and Brain addresses
// Sets pointer addresses value as base addresses
Init_Machine_And_Brain:
	LDR R2, =MACHINE_POINTER_ADDRESS
	LDR R9, =MACHINE_BASE_ADDRESS
	STR R9,[R2]
	LDR R2, =BRAIN_POINTER_ADDRESS
	LDR R9, =BRAIN_BASE_ADDRESS
	STR R9,[R2]
	BX LR
	
// Initialises the IRQ73 and IRQ80 Interrupts
InitInterrupts:

	MOV R1, #0b11010010 // interrupts masked, MODE = IRQ
	MSR CPSR_c, R1 // change to IRQ mode
	LDR SP, =0xFFFFFFFF - 3 // set IRQ stack to A9 onchip memory

	/* Change to SVC (supervisor) mode with interrupts disabled */
	MOV R1, #0b11010011 // interrupts masked, MODE = SVC
	MSR CPSR, R1 // change to supervisor mode
	LDR SP, =0x3FFFFFFF - 3 // set SVC stack to top of DDR3 memory
	BL CONFIG_GIC // configure the ARM GIC

	LDR R0, =UART_BASE // pushbutton KEY base address
	MOV R1, #0xF // set interrupt mask bits
	STR R1, [R0, #0x4] // interrupt mask register (base + 8)


	LDR R0, =BUTTONS_BASE // pushbutton KEY base address
	MOV R1, #0xF // set interrupt mask bits
	STR R1, [R0, #0x8] // interrupt mask register (base + 8)
	
	MOV R0, #0b01010011 // IRQ unmasked, MODE = SVC
	MSR CPSR_c, R0
IDLE:
	B IDLE // main program simply idles

/* Define the exception service routines */
/*--- Undefined instructions --------------------------------------------------*/
SERVICE_UND:
	B SERVICE_UND
/*--- Software interrupts -----------------------------------------------------*/
SERVICE_SVC:
	B SERVICE_SVC
/*--- Aborted data reads ------------------------------------------------------*/
SERVICE_ABT_DATA:
	B SERVICE_ABT_DATA
/*--- Aborted instruction fetch -----------------------------------------------*/
SERVICE_ABT_INST:
	B SERVICE_ABT_INST

/*--- IRQ ---------------------------------------------------------------------*/
SERVICE_IRQ:
	PUSH {R0-R11, LR}
	/* Read the ICCIAR from the CPU Interface */
	LDR R4, =0xFFFEC100
	LDR R5, [R4, #0x0C] // read from ICCIAR
// According to the Interrupt type, it redirects to the relevant label
FPGA_IRQ1_HANDLER:
	// If IRQ Is 80 It is a JTAG UART Input Interrupt
	CMP R5, #80
	BEQ UAT_INTERRUPT
	// If IRQ Is 73 It is a Push Button Interrupt
	CMP R5, #73
	BEQ KEY_ISR
	
UNEXPECTED:
	B UNEXPECTED // if not recognized, stop here
EXIT_IRQ:
	/* Write to the End of Interrupt Register (ICCEOIR) */
	STR R5, [R4, #0x10] // write to ICCEOIR
	POP {R0-R11, LR}
	SUBS PC, LR, #4
	
SERVICE_FIQ:
	B SERVICE_FIQ	
	
CONFIG_GIC:
	PUSH {LR}
/* To configure the FPGA KEYS interrupt (ID 73):
* 1. set the target to cpu0 in the ICDIPTRn register
* 2. enable the interrupt in the ICDISERn register */

/* CONFIG_INTERRUPT (int_ID (R0), CPU_target (R1)); */
	// Sets config for JTAG UART and Push Button Interrupts
	MOV R0, #80 
	MOV R1, #1 // this field is a bit-mask; bit 0 targets cpu0
	BL CONFIG_INTERRUPT
	MOV R0, #73
	MOV R1, #1
	BL CONFIG_INTERRUPT
	/* configure the GIC CPU Interface */
	LDR R0, =0xFFFEC100 // base address of CPU Interface
	
	/* Set Interrupt Priority Mask Register (ICCPMR) */
	LDR R1, =0xFFFF // enable interrupts of all priorities levels
	STR R1, [R0, #0x04]
	
	/* Set the enable bit in the CPU Interface Control Register (ICCICR).
	* This allows interrupts to be forwarded to the CPU(s) */
	MOV R1, #1
	STR R1, [R0]
	
	/* Set the enable bit in the Distributor Control Register (ICDDCR).
	* This enables forwarding of interrupts to the CPU Interface(s) */
	LDR R0, =0xFFFED000
	STR R1, [R0]
	POP {PC}

/*
* Configure registers in the GIC for an individual Interrupt ID
* We configure only the Interrupt Set Enable Registers (ICDISERn) and
* Interrupt Processor Target Registers (ICDIPTRn). The default (reset)
* values are used for other registers in the GIC
* Arguments: R0 = Interrupt ID, N
* R1 = CPU target
*/
CONFIG_INTERRUPT:
	PUSH {R4-R5, LR}
/* Configure Interrupt Set-Enable Registers (ICDISERn).
* reg_offset = (integer_div(N / 32) * 4
* value = 1 << (N mod 32) */
	LSR R4, R0, #3 // calculate reg_offset
	BIC R4, R4, #3 // R4 = reg_offset
	LDR R2, =0xFFFED100
	ADD R4, R2, R4 // R4 = address of ICDISER
	AND R2, R0, #0x1F // N mod 32
	MOV R5, #1 // enable
	LSL R2, R5, R2 // R2 = value
	
/* Using the register address in R4 and the value in R2 set the
* correct bit in the GIC register */
	LDR R3, [R4] // read current register value
	ORR R3, R3, R2 // set the enable bit
	STR R3, [R4] // store the new register value
	
/* Configure Interrupt Processor Targets Register (ICDIPTRn)
* reg_offset = integer_div(N / 4) * 4
* index = N mod 4 */
	BIC R4, R0, #3 // R4 = reg_offset
	LDR R2, =0xFFFED800
	ADD R4, R2, R4 // R4 = word address of ICDIPTR
	AND R2, R0, #0x3 // N mod 4
	ADD R4, R2, R4 // R4 = byte address in ICDIPTR
	
/* Using register address in R4 and the value in R2 write to
* (only) the appropriate byte */
	STRB R1, [R4]
	POP {R4-R5, PC}	
	
	





// This function and the relevant functions are
// used to show total information count when user decided to see brain data
// Total data count is hold in the R0 register
Display_Number:
	MOV R0, R9
	LDR R2, Seven_Segment_Base_Addres
	MOV R3, #0 // COUNTER_THOUSAND (Holds 1000's digit)
	MOV R4, #0 // COUNTER_HUNDRED (Holds 100's digit)
	MOV R5, #0 // COUNTER_TEN (Holds 10's digit)
	MOV R6, #0 // COUNTER_ONE (Holds 1's digit)
	MOV R7, #0 // 
	MOV R8, #0 // 
	MOV R9, #0 // 
	B IS_THERE_THOUSAND

Get_Zero_Hexa:
	LDR R8, [R7]
	BX LR
// Finds Hexa number for relevant value
FIND_HEXA_NUMBER:
	CMP R9,#0
	BEQ Get_Zero_Hexa
	
	LDR R8, [R7] , #4
	SUB R9,R9,#1
	CMP R9,#0
	BNE FIND_HEXA_NUMBER
	LDR R8, [R7]
	BX LR

// Checks if the current number has 1000's digit
IS_THERE_THOUSAND:
	CMP R0,#1000
	BGE LOOP_THOUSAND
	LDR R3 ,HEXTABLE
	B IS_THERE_HUNDRED
// Checks if the current number has 100's digit
IS_THERE_HUNDRED:
	CMP R0,#100
	BGE LOOP_HUNDRED
	LDR R4 ,HEXTABLE
	B IS_THERE_TEN
// Checks if the current number has 10's digit
IS_THERE_TEN:
	CMP R0,#10
	BGE LOOP_TEN
	LDR R5 ,HEXTABLE
	B LOOP_ONE
// Loops in 1000's until find the value of 1000's digit
LOOP_THOUSAND://R3
	SUB R0,R0,#1000
	CMP R0,#1000
	ADD R3,R3,#1
	BGE LOOP_THOUSAND
	
	LDR R7,=HEXTABLE
	MOV R9,R3
	BL FIND_HEXA_NUMBER
	MOV R3,R8
	MOV R8,#0
	B IS_THERE_HUNDRED
// Loops in 100's until find the value of 100's digit
LOOP_HUNDRED://R4
	SUB R0,R0,#100
	CMP R0,#100
	ADD R4,R4,#1
	BGE LOOP_HUNDRED
	
	LDR R7,=HEXTABLE	
	MOV R9,R4
	BL FIND_HEXA_NUMBER
	MOV R4,R8
	MOV R8,#0
	
	B IS_THERE_TEN
// Loops in 10's until find the value of 10's digit
LOOP_TEN://R5
	SUB R0,R0,#10
	CMP R0,#10
	ADD R5,R5,#1
	BGE LOOP_TEN
	
	LDR R7,=HEXTABLE	
	MOV R9,R5
	BL FIND_HEXA_NUMBER
	MOV R5,R8
	MOV R8,#0
	
	B LOOP_ONE
// Not run looping in the 1's, directly gets the remainder value
LOOP_ONE://R6
	MOV R6,R0
	LDR R7,=HEXTABLE	
	MOV R9,R6
	BL FIND_HEXA_NUMBER
	MOV R6,R8
	MOV R8,#0
	B Write_All_Digits
// Writes all found digits to the seven-segment display
Write_All_Digits:
	MOV R0,#0
	ADD R0,R0,R6
	LSL R5, #8
	ADD R0,R0,R5
	LSL R4, #16
	ADD R0,R0,R4
	LSL R3, #24
	ADD R0,R0,R3
	STR R0,[R2]
	CMP R10,#1
	BEQ Reset_Brain_Info_End_Return
	B End_Show_Brain_Info








/* Push Button Interrupts are used in order to 
change brains or machine's status bits which are called "modes". 
When the brain is in FOCUSED mode it can get information. 
However in Diffused mode brain is not getting information. 
Similarly, when the machine is in OPEN mode it can inject info into the brain, 
however in the CLOSED mode it can not inject new information into the brain. */

KEY_ISR:
	LDR R0, =BUTTONS_BASE // base address of pushbutton KEY port	
	LDR R9, =BRAIN_STATUS_ADDRESS // base address of pushbutton KEY port

	LDR R1, [R0, #0xC] // read edge capture register
	MOV R2, #0xF
	STR R2, [R0, #0xC] // clear the interrupt
// Checks if first push button clicked
CHECK_KEY0:
	MOV R3, #0x1
	ANDS R3, R3, R1 // check for KEY0
	BEQ CHECK_KEY1
	
	// Sets the Brain's current mode to FOCUSED and 
	// prints relevant info to the JTAG UART
	LDR R3, =BRAIN_STATUS_ADDRESS
	LDR R1, =BRAIN_FOCUSED_STATUS_MASK
	STR R1,[R3]
	LDR R6, =DECISION_STATUS_UPDATE_FOCUSED_INFO_STRING
	BL LoadText
	
	B END_KEY_ISR
// Checks if second push button clicked
CHECK_KEY1:
	MOV R3, #0x2
	ANDS R3, R3, R1 // check for KEY1
	BEQ CHECK_KEY2
	
	// Sets the Brain's current mode to DIFFUSED and 
	// prints relevant info to the JTAG UART
	LDR R3, =BRAIN_STATUS_ADDRESS
	LDR R1, =BRAIN_DIFFUSED_STATUS_MASK
	STR R1,[R3]
	LDR R6, =DECISION_STATUS_UPDATE_DIFFUSED_INFO_STRING
	BL LoadText
	
	B END_KEY_ISR
// Checks if third push button clicked
CHECK_KEY2:
	MOV R3, #0x4
	ANDS R3, R3, R1 // check for KEY2
	BEQ IS_KEY3
	
	// Sets the Machine's current mode to OPEN and 
	// prints relevant info to the JTAG UART
	LDR R3, =MACHINE_STATUS_ADDRESS
	LDR R1, =MACHINE_OPEN_STATUS_MASK
	STR R1,[R3]
	LDR R6, =MACHINE_STATUS_UPDATE_OPEN_INFO_STRING
	BL LoadText
	
	B END_KEY_ISR
// Checks if fourth push button clicked
IS_KEY3:
	// Sets the Machine's current mode to CLOSED and 
	// prints relevant info to the JTAG UART
	LDR R3, =MACHINE_STATUS_ADDRESS
	LDR R1, =MACHINE_CLOSED_STATUS_MASK
	STR R1,[R3]
	LDR R6, =MACHINE_STATUS_UPDATE_CLOSED_INFO_STRING
	BL LoadText
END_KEY_ISR:
	B EXIT_IRQ
	














// Triggers when IRQ 80 (JTAG UART) Interrupt occured.
// It occurs when user input a character to the relevant interface
Init_Input_Loop:
	LDR  r1, =UART_BASE
	MOV R10, #0
	ADD R10,R1,#4
	MOV R7, #0b1
	STR R7,[R10]
	B InputLoop // Jumps to the loop after UART is ready
// The main loop of the application when IRQ 80 triggered. 
// Depending on the mode or current panel, it is evaluating the user's 
// input and decide to triggered a variety of different events.
InputLoop:
	LDRH R10, [R1]
	TST  R10, #0x8000
	BEQ END_INPUT_LOOP 
	AND R10,R10,#0xFF
	STR  R10, [r1] 
	CMP R10,#0x21 // Checks if entered char is "!" 
	BEQ Put_Info_To_Brain // If it is "!" puts info the brain
	B Is_Waiting_Decision // Else checks if entered input is a decision
	
	B InputLoop // Jumps to the loop again

// #0b1 is indicates writing mode, If it is not in the writing mode,
// This function redirects to the a function which checks current decision masks
Is_Waiting_Decision:
	CMP R12,#0b1
	BNE Check_Input_MASK
	B Store_Info_Input_To_Machine
	
End_Info_Input:
	// Resets pointer of the Machine
	LDR R2, =MACHINE_POINTER_ADDRESS
	LDR R9, =MACHINE_BASE_ADDRESS
	STR R9,[R2]
	
	// Resets data of the Machine
	PUSH {R0-R10}
	LDR R10, =MACHINE_RESET_ADDRESS
	LDR R2, =MACHINE_RESET_MASK
	AND R2,R2,#0
	STR R2,[R10]
	POP {R0-R10}
	
	LDR R12, =PANEL_DECISION_MASK // Sets R12 to panel decision mask again
	
	// Checks the brain's current mode on injection, if brain is FOCUSED,
	// it allows information injection and prints sucess message. If Brain
	// is in DIFFUSED mode it cancels the injection and prints error message
	PUSH {R0-R10}
	LDR R3, =BRAIN_STATUS_ADDRESS
	LDR R1,[R3]
	LDR R4, =BRAIN_FOCUSED_STATUS_MASK
	CMP R1,R4
	LDREQ  R6, =INFO_INPUT_SUCESS
	LDRNE  R6, =INFO_INPUT_PROHIBITED_IN_DIFFUSED_MODE_STRING
	BL LoadText
	POP {R0-R10}
	
	// Returns Decision panel again
	LDR  R6, =DECISION_PANEL_STRING
	BL LoadText
	
	B END_INPUT_LOOP

// Checks if the current decision is for which section, There are
// three sections, "Panel section" is for allowing access to Brain and Machine
// "Brain section" is for performing Brain's operations, "Machine section" is 
// for performing Machine operations
Check_Input_MASK:
	CMP R12,#0b10 
	BEQ Panel_Decision
	CMP R12,#0b100 
	BEQ Brain_Decision
	CMP R12,#0b1000 
	BEQ Machine_Decision
	
// Redirects to the relevant section from the main panel
// according to the entered number.
Panel_Decision:
	MOV R11, #0x0a
	STR R11, [R1]
	
	CMP R10,#0x31 // 1 is for Brain panel
	BEQ Open_Brain_Panel
	CMP R10,#0x32 // 2 is for Machine panel
	BEQ Open_Machine_Panel
	
	B Invalid_Request // Triggers if an invalid input entered

// It shows an error message if entered input is not in the possible decisions
Invalid_Request:
	LDR  R6, =INVALID_REQUEST_STRING
	BL LoadText
	B InputLoop
// Sets decision register R12 to Machine mode mask
Open_Machine_Panel:
	
	LDR  R6, =MACHINE_DECISION_STRING
	BL LoadText
	LDR R12, =MACHINE_MODE_MASK
	B InputLoop
// Sets the decision register R12 to Brain mode mask
Open_Brain_Panel:
	LDR  R6, =BRAIN_DECISION_STRING
	BL LoadText
	LDR R12, =BRAIN_MODE_MASK
	B InputLoop
// Opens writing mode and allows users 
// to the enter the information which will be injected into the brain.
Injection_Decision:
	LDR  R6, =INFO_PROMPT_STRING
	BL LoadText
	LDR R12, =WRITING_MODE_MASK
	B InputLoop
// Opens machine panel when machine mask bit assigned to R12 decision register.
Machine_Decision:
	MOV R11, #0x0a
	STR R11, [R1]
	
	CMP R10,#0x31 // 1 opens injection panel
	BEQ Machine_Check_Injection

	CMP R10,#0x32 // 2 prints machine status
	BEQ Show_Machine_Status
	
	B Invalid_Request
// Checks if Machine is "OPEN" mode, if so allows information injection
Machine_Check_Injection:
	PUSH {R0-R10}
	LDR R3, =MACHINE_STATUS_ADDRESS
	LDR R1,[R3]
	LDR R4, =MACHINE_OPEN_STATUS_MASK
	CMP R1,R4
	POP {R0-R10}
	BEQ Injection_Decision // Allows if the mode is "OPEN" mode
	B Machine_Cancel_Info_Injection // Cancels if the mode is "CLOSED" mode
// Cancels info injection on the machine when it is in "CLOSED" mode
Machine_Cancel_Info_Injection:
	LDR R6, =MACHINE_STATUS_CLOSED_INFO_STRING
	BL LoadText
	B Show_Panel
// Shows if Machine is in "OPEN" or "CLOSED" state
// Also prints the current state of the Machine
Show_Machine_Status:
	PUSH {R0-R10}
	LDR R3, =MACHINE_STATUS_ADDRESS
	LDR R1,[R3]
	LDR R4, =MACHINE_OPEN_STATUS_MASK
	LDR R2, =MACHINE_STATUS_OPEN_INFO_STRING
	CMP R1,R4
	MOVEQ R6,R2
	BLEQ LoadText
	
	LDR R4, =MACHINE_CLOSED_STATUS_MASK
	LDR R2, =MACHINE_STATUS_CLOSED_INFO_STRING
	CMP R1,R4
	MOVEQ R6,R2
	BLEQ LoadText
	
	POP {R0-R10}
	B Show_Panel
// Reads the decision of the user when it is in the brain panel
Brain_Decision:
	MOV R11, #0x0a
	STR R11, [R1]
	
	CMP R10,#0x31 // 1 shows the Brain's data
	BEQ Show_Brain_Info
	CMP R10,#0x32 // 2 Shows the Brain's status
	BEQ Show_Brain_Status
	CMP R10,#0x33 // 3 Resets the Brain
	BEQ Reset_Brain_Info
	
	B Invalid_Request
	
// Shows if Brain is in "FOCUSED" or "DIFFUSED" state
// Also prints the current state of the Brain
Show_Brain_Status:
	PUSH {R0-R10}
	LDR R3, =BRAIN_STATUS_ADDRESS
	LDR R1,[R3]
	LDR R4, =BRAIN_FOCUSED_STATUS_MASK
	LDR R2, =DECISION_STATUS_FOCUSED_STRING
	CMP R1,R4
	MOVEQ R6,R2
	BLEQ LoadText
	
	LDR R4, =BRAIN_DIFFUSED_STATUS_MASK
	LDR R2, =DECISION_STATUS_DIFFUSED_STRING
	CMP R1,R4
	MOVEQ R6,R2
	BLEQ LoadText
	
	POP {R0-R10}
	B Show_Panel
	
// Shows the Brain's stored information data by 
// printing the data from the base address to the
// address which is pointed by the pointer address
// Also displays the total information count in the
// Seven-segment display
Show_Brain_Info:
	LDR R2, =BRAIN_POINTER_ADDRESS
	LDR R9, [R2]
	LDR R2, =BRAIN_BASE_ADDRESS
	MOV R6,R2
	BL LoadText
	LDR R2, =BRAIN_POINTER_ADDRESS
	LDR R9, [R2]
	LDR R2, =BRAIN_BASE_ADDRESS
	SUB R9,R9,R2
	MOV R10,#0
	
	LDR R2, =BRAIN_COUNTER_ADDRESS
	STR R9,[R2]
	PUSH {R0-R10}
	B Display_Number

// Ends show Brain info function
End_Show_Brain_Info:
	POP {R0-R10}
	B Show_Panel
// Resets the all information inside the Brain
Reset_Brain_Info:
	LDR R10, =BRAIN_RESET_ADDRESS
	LDR R2, =BRAIN_RESET_MASK
	STR R2,[R10]
	
	LDR R2, =BRAIN_POINTER_ADDRESS
	LDR R9, [R2]
	LDR R2, =BRAIN_BASE_ADDRESS
	
	LDR R10,[R10]
	CMP R10,#1
	BEQ Reset_Brain_Info_Loop // Jumps to the loop
// Resets the memory addresses from base address to the pointer's content address
Reset_Brain_Info_Loop:
	LDR R10, =MEMORY_RESET_MASK
	STR R10, [R2],#4
	CMP R2,R9
	BGE Reset_Brain_Info_End
	B Reset_Brain_Info_Loop

// Ends the resetting operation by setting reset bit(control bit) to 1
Reset_Brain_Info_End:
	MOV R9,#0
	MOV R10,#1
	PUSH {R0-R10}
	B Display_Number

	
// After the reset operation is ended, 
// it changes the control state from 1 to 0 
// in order to indicate the reset operation is finished. 
// Also directs the user to the main panel.
Reset_Brain_Info_End_Return:	
	POP {R0-R10}
	
	LDR R10, =BRAIN_RESET_ADDRESS
	LDR R2, =BRAIN_RESET_MASK
	AND R2,R2,#0
	STR R2,[R10]
	
	LDR R10, =BRAIN_POINTER_ADDRESS
	LDR R2, =BRAIN_BASE_ADDRESS
	STR R2,[R10]
	LDR R12, =PANEL_DECISION_MASK
	LDR R6, =BRAIN_RESET_STRING
	BL LoadText
	LDR R6, =DECISION_PANEL_STRING
	BL LoadText
	B END_INPUT_LOOP
_stop:
	B _stop

// Runs UAT Interrupt
UAT_INTERRUPT:
	B Init_Input_Loop
// Shows main panel
Show_Panel:
	LDR R12, =PANEL_DECISION_MASK
	LDR  R6, =DECISION_PANEL_STRING
	BL LoadText
	B END_INPUT_LOOP
// Ends interrupts
END_INPUT_LOOP:
	B EXIT_IRQ
	
// In the beginning, 
// During the injection process, 
// puts written information on the machine. 
Store_Info_Input_To_Machine:
	LDR R2, =MACHINE_POINTER_ADDRESS
	LDR R9, [R2]
	STRB R10, [R9]
	ADD R9,R9,#1
	STR R9,[R2]
	B InputLoop

// Reset the machine after injection process is finished
Reset_Info_Input_Machine:
	LDR R2, =MACHINE_POINTER_ADDRESS
	LDR R9, [R2]
	LDR R2, =MACHINE_BASE_ADDRESS
	
	PUSH {R0-R10}
	LDR R10, =MACHINE_RESET_ADDRESS
	LDR R2, =MACHINE_RESET_MASK
	STR R2,[R10]
	POP {R0-R10}
	
	B Reset_Info_Helper_Loop
// Resets the Machine in a loop by resetting the addreses 
// from base address to pointer address
Reset_Info_Helper_Loop:
	LDR R10, =MEMORY_RESET_MASK
	STR R10, [R2],#4
	CMP R2,R9
	BGE End_Info_Input
	B Reset_Info_Helper_Loop
// Puts info on the brain, however, 
// if the brain is in DIFFUSED mode, 
// it cancels the info injection operation
Put_Info_To_Brain:
	// Cancels the operation when Brain is in DIFFUSED mode
	PUSH {R0-R10}
	LDR R3, =BRAIN_STATUS_ADDRESS
	LDR R1,[R3]
	LDR R4, =BRAIN_FOCUSED_STATUS_MASK
	CMP R1,R4
	POP {R0-R10}
	BNE Reset_Info_Input_Machine
	
	// Gets the Machine and Brain's pointer addresses
	LDR R2, =MACHINE_POINTER_ADDRESS
	LDR R9, [R2]
	LDR R2, =MACHINE_BASE_ADDRESS
	LDR R7, =BRAIN_POINTER_ADDRESS
	LDR R0,[R7]
	B Put_Info_To_Brain_Helper_Loop
// It takes the information from the Machine 
// and puts it into the brain simultaneously.
Put_Info_To_Brain_Helper_Loop:
	LDRB R10, [R2]
	STRB R10,[R0]
	
	ADD R2,R2,#1
	ADD R0,R0,#1
	STR R0,[R7]
	CMP R9,R2
	BGE Put_Info_To_Brain_Helper_Loop
	SUB R0,R0,#1
	MOV R10, #0x0A
	STRB R10,[R0]
	ADD R0,R0,#1
	STRB R10,[R0]
	B Reset_Info_Input_Machine
	
	
// This function is used for printing strings to the JAG UART. 
// Firstly, initializes the timer and UART addresses.	
LoadText:
	//Init Timer
	LDR R11, =0xFFFEC600 // PRIVATE TIMER
	LDR R10,=12000000
	STR R10,[R11]
	MOV R10, #0b011 
	STR R10, [R11, #0x8] 

	LDR  r1, =UART_BASE
	MOV R8,R7
	MOV R7,R6
	B WriteText
// Writes the text inside the address in the R6 register
// until reading the memory address which is empty.
WriteText:
	LDRB r0, [R7]    // load a single byte from the string
	CMP  r0, #0
	BEQ  END_Write_Text  // stop when the null character is found
	CMP  r0, #0xaa
	BEQ  END_Write_Text
	B WAIT
	
Write_Text_Helper:
	STR  r0, [r1]    // copy the character to the UART DATA field
	ADD  R7, R7, #1  // move to next character in memory
	B WriteText
// Ends write text 
END_Write_Text:
	MOV R7,R8
	MOV R8,#0
	MOV R10, #0b000
	STR R10, [R11, #0x8] 
	BX LR
// Waits for a while after every character is written
WAIT: 
	LDR R10, [R11, #0xC] // read timer status
	CMP R10, #0
	BEQ WAIT
	STR R10, [R11, #0xC] 
	B Write_Text_Helper

	
.data  // Data Section
INFO_PROMPT_STRING: 
.asciz    "Enter Information You Want to Inject \n > "
MACHINE_DECISION_STRING: 
.asciz "\n Enter 1 to Open Injection , Enter 2 to see Machine's Status \n >"
BRAIN_DECISION_STRING: 
.asciz    "Enter 1 to see Brain Data, Enter 2 to see Brain's status, Enter 3 to reset Brain \n > "
BRAIN_RESET_STRING:
.asciz    "Brain reset successfully\n > "
INFO_INPUT_SUCESS:
.asciz    "\n Information injection to the Brain is Successfull! \n"
INVALID_REQUEST_STRING:
.asciz    "\n Please enter a valid decision input \n"
DECISION_PANEL_STRING: 
.asciz "\n Enter 1 to open Brain Panel , Enter 2 to open Machine Panel \n >"
DECISION_STATUS_UPDATE_FOCUSED_INFO_STRING: 
.asciz "\n Brain Set To FOCUSED State "
DECISION_STATUS_UPDATE_DIFFUSED_INFO_STRING: 
.asciz "\n Brain Set To DIFFUSED State "
DECISION_STATUS_FOCUSED_STRING: 
.asciz "\n Brain Is FOCUSED you can inject information \n"
DECISION_STATUS_DIFFUSED_STRING: 
.asciz "\n Brain Is DIFFUSED you can't inject information \n"
MACHINE_STATUS_UPDATE_OPEN_INFO_STRING: 
.asciz "\n Machine Set To OPEN State "
MACHINE_STATUS_UPDATE_CLOSED_INFO_STRING: 
.asciz "\n Machine Set To CLOSED State "
MACHINE_STATUS_OPEN_INFO_STRING: 
.asciz "\n Machine is OPEN you can enter information "
MACHINE_STATUS_CLOSED_INFO_STRING: 
.asciz "\n Machine is CLOSED you can't enter information "
MACHINE_INPUT_PROHIBITED_IN_CLOSED_MODE_STRING: 
.asciz "\n Brain Is in DIFFUSED mode therefore you can't enter information \n"
INFO_INPUT_PROHIBITED_IN_DIFFUSED_MODE_STRING: 
.asciz "\n Brain Is in DIFFUSED mode therefore you can't enter information \n"
TOTAL_INFO_COUNT_STRING: 
.asciz "\n Total Info Count:"

.end