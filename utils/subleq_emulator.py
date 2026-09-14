#!/usr/bin/env python3
"""
OISC (One Instruction Set Computer) SUBLEQ Emulator
Synthesizes higher-level assembly operations (MOV, ADD, JMP) using only subtraction and conditional branching.
"""


class SubleqEmulator:
    def __init__(self, memory, pc_start=0):
        self.memory = list(memory)
        self.pc = pc_start
        self.initial_memory = list(memory)
        self.step_count = 0
        self.trace = []

    def step(self):
        if self.pc < 0 or self.pc + 2 >= len(self.memory):
            return False  # Halt condition (Program Counter out of bounds)

        # Read the three arguments of the SUBLEQ instruction
        a_addr = self.memory[self.pc]
        b_addr = self.memory[self.pc + 1]
        c_addr = self.memory[self.pc + 2]

        # Hard-coded standard negative values for immediate halt
        if a_addr < 0 or b_addr < 0:
            return False

        val_a = self.memory[a_addr]
        val_b = self.memory[b_addr]

        # Core operation: B = B - A
        new_val = val_b - val_a
        self.memory[b_addr] = new_val

        old_pc = self.pc
        # Branching condition: if B <= 0, jump to C; else PC = PC + 3
        if new_val <= 0:
            self.pc = c_addr
        else:
            self.pc += 3

        self.trace.append({
            "step": self.step_count,
            "pc": old_pc,
            "args": (a_addr, b_addr, c_addr),
            "operation": f"Mem[{b_addr}] ({val_b}) = Mem[{b_addr}] ({val_b}) - Mem[{a_addr}] ({val_a}) -> {new_val}",
            "branch": f"Jumped to {c_addr} (Reason: {new_val} <= 0)" if self.pc == c_addr else f"Step forward to {self.pc} (Reason: {new_val} > 0)",
            "memory_state": list(self.memory)
        })
        self.step_count += 1
        return True

    def run(self, max_steps=1000):
        while self.step():
            if self.step_count >= max_steps:
                break
        return self.step_count


def explain_add_synthesis():
    print("\n" + "=" * 80)
    print("  SYNTHESIZING ADD (Y = Y + X) IN SUBLEQ  ")
    print("=" * 80)
    print("Mathematically, we cannot 'add' directly. We must use a temporary zero location (Z).")
    print("We perform subtraction twice:")
    print("  1. Z = Z - X   (Since Z started at 0, Z is now -X)")
    print("  2. Y = Y - Z   (Y = Y - (-X) which mathematically equals Y + X!)")
    print("  3. Z = Z - Z   (Zero out Z back to 0 to keep our temporary location clean)")
    print("-" * 80)


def explain_mov_synthesis():
    print("\n" + "=" * 80)
    print("  SYNTHESIZING MOV (Y = X) IN SUBLEQ  ")
    print("=" * 80)
    print("To copy X to Y, we must first clear Y, then subtract X into a temp space, and shift it.")
    print("  1. Y = Y - Y   (Clears Y to 0)")
    print("  2. Z = Z - X   (Z becomes -X, assuming Z was 0)")
    print("  3. Y = Y - Z   (Y = 0 - (-X) = X)")
    print("  4. Z = Z - Z   (Zero out Z back to 0)")
    print("-" * 80)


def run_add_demo():
    explain_add_synthesis()

    # Memory Layout:
    # [0] X = 5
    # [1] Y = 7
    # [2] Z = 0 (Temp)
    # [3] Dummy/unused/halt helper
    # [4-15] Program instructions
    mem = [
        5,   # [0] Input X
        7,   # [1] Input Y
        0,   # [2] Temporary register (Z)
        0,   # [3] Unused

        # Code starts at Index 4
        0, 2, 7,    # [4]  SUBLEQ X, Z, 7   -> Subtract X from Z (-5). Jump to 7
        2, 1, 10,   # [7]  SUBLEQ Z, Y, 10  -> Subtract Z from Y (7 - (-5) = 12). Jump to 10
        2, 2, 13,   # [10] SUBLEQ Z, Z, 13  -> Clean up Z to 0. Jump to 13
        -1, -1, -1  # [13] Halt
    ]

    emu = SubleqEmulator(mem, pc_start=4)
    emu.run()

    print(f"Initial State: X = {mem[0]}, Y = {mem[1]}, Z = {mem[2]}")
    print(f"Final State:   X = {emu.memory[0]}, Y = {emu.memory[1]} (Expected: 12), Z = {emu.memory[2]}\n")

    for state in emu.trace:
        print(f"[{state['step']+1}] Instruction at PC {state['pc']}: SUBLEQ {state['args']}")
        print(f"    Action: {state['operation']}")
        print(f"    Branch: {state['branch']}")
        print(f"    RAM:    {state['memory_state'][:4]} ...")
        print("-" * 60)


def run_mov_demo():
    explain_mov_synthesis()

    # Memory Layout:
    # [0] X = 42 (Value to copy)
    # [1] Y = 99 (Value to be overwritten)
    # [2] Z = 0  (Temp)
    # [3] Unused
    mem = [
        42,  # [0] Input X
        99,  # [1] Input Y (to overwrite)
        0,   # [2] Temporary register (Z)
        0,   # [3] Unused

        # Code starts at Index 4
        1, 1, 7,    # [4]  SUBLEQ Y, Y, 7   -> Clear Y to 0. Jump to 7
        0, 2, 10,   # [7]  SUBLEQ X, Z, 10  -> Subtract X from Z (-42). Jump to 10
        2, 1, 13,   # [10] SUBLEQ Z, Y, 13  -> Subtract Z from Y (0 - (-42) = 42). Jump to 13
        2, 2, 16,   # [13] SUBLEQ Z, Z, 16  -> Clean up Z to 0. Jump to 16
        -1, -1, -1  # [16] Halt
    ]

    emu = SubleqEmulator(mem, pc_start=4)
    emu.run()

    print(f"Initial State: X = {mem[0]}, Y = {mem[1]}, Z = {mem[2]}")
    print(f"Final State:   X = {emu.memory[0]}, Y = {emu.memory[1]} (Expected: 42), Z = {emu.memory[2]}\n")

    for state in emu.trace:
        print(f"[{state['step']+1}] Instruction at PC {state['pc']}: SUBLEQ {state['args']}")
        print(f"    Action: {state['operation']}")
        print(f"    Branch: {state['branch']}")
        print(f"    RAM:    {state['memory_state'][:4]} ...")
        print("-" * 60)


if __name__ == "__main__":
    print("=" * 80)
    print("                OISC SUBLEQ INTERACTIVE SIMULATOR (ARCHITECTURE ZERO)       ")
    print("=" * 80)
    print("SUBLEQ utilizes exactly ONE instruction: SUBLEQ A, B, C")
    print("Meaning: Subtract Mem[A] from Mem[B], store in Mem[B]. If Mem[B] <= 0, jump to C.")

    run_add_demo()
    run_mov_demo()

    print("\n[Done] Emulator execution completed successfully.")
