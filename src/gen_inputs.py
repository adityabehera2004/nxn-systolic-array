#!/usr/bin/env python3

# this file is meant to be run by make

# it randomly generates the inputs mem_a.hex and mem_b.hex in the working directory
# note: mem_b is really more like mem_w since it holds all the weight matrices
# if I had designed this, I would have probably put mem_a and mem_b together in mem_m
# but I won't change it since the top IO spec uses A and B to access the first matrix and all the weights

# it also creates mem_i.hex to store the instruction sequence for the testbench to read
# no I does an NxN identity multiply (tests correcntness for a very simple case)
# I=A or I=A,0 does an IxI identity multiply (tests tiling for square matrices)
# I=A,B or I=A,B,0 does an MxN identity multiply (tests tiling for non-square matrices)
# I=A,B,C,... or I=A,B,C,...,0 does a full MMM chain with the specified dimensions (tests correctness on more complex sequences)
# note: 0 terminator is optional but it will always appear in mem_i.hex

# it also creates ref_out.hex which is the expected output and can be compared against sim_out.hex
# note: mem_o is not created by this script or testbench (output is saved in ref_out and sim_out)

# this script also creates params.mk which contains sizes and strings for testbench

import argparse
import numpy as np
import os

SCALE = 256       # Q8.8 scale factor (2^8)
ACC_SCALE = 65536 # Q16.16 scale factor (2^16)
# we use Q16.16 accumulators in between matmuls because Q8.8*Q8.8 = Q16.16

def float_to_q8_8(fval):
   v = int(round(fval * SCALE))
   v = max(-32768, min(32767, v))
   return v

def q8_8_to_float(ival):
   return ival / SCALE

def q16_16_to_q8_8(val_i32):
   shifted = int(val_i32) >> 8
   return max(-32768, min(32767, shifted))

def q8_8_to_q16_16(val_i16):
   shifted = int(val_i16) << 8
   return max(-2147483648, min(2147483647, shifted))

def mat_to_q8_8(mat):
   # converts a numpy float matrix to int16 (Q8.8) numpy array
   vfunc = np.vectorize(float_to_q8_8)
   return vfunc(mat).astype(np.int16)

def matmul_q8_8(A_int, B_int):
   A = A_int.astype(np.int64)  # A is really 16 bit (Q8.8) but we use int64 because python
   B = B_int.astype(np.int64)  # B is really 16 bit (Q8.8) but we use int64 because python
   return (A @ B).astype(np.int64)  # output is also really 32 bit (Q16.16) but we use int64 because python

def write_hex16(filename, data_int16):
   # writes each int16 value as a 4 digit hex string to each line of the file (mem_a and mem_b)
   with open(filename, 'w') as f:
      for v in data_int16.flatten():
         u = int(v) & 0xFFFF
         f.write(f"{u:04x}\n")

def write_hex32(filename, data_int32, add_comments=False):
   # writes each int32 value as an 8 digit hex string to each line of the file (mem_i and ref_out)
   with open(filename, 'w') as f:
      for idx, v in enumerate(data_int32.flatten()):
         if add_comments and (idx % 16) == 0:
            # this is just for ref_out to match the format of sim_out
            # sim_out uses $writememh which adds an address comment every 16 words
            # this is purely aesthetic and has no effect on functionality
            # I just added it so it would be easier to compare visually
            f.write(f"// 0x{idx:08x}\n")
         u = int(v) & 0xFFFFFFFF
         f.write(f"{u:08x}\n")

def main():
   parser = argparse.ArgumentParser(description="Generate systolic array test data")
   parser.add_argument('--N',    type=int, default=4,  help='Systolic array size')
   parser.add_argument('--I',    type=str, default=None, help='Instruction sequence: single integer for IxI identity multiply (e.g. 4) or full sequence for MMM chain (e.g. 32,16,64,8,16,0)')
   parser.add_argument('--seed', type=int, default=42, help='Random seed')
   parser.add_argument('--wdir', type=str, default='.', help='Working directory')
   args = parser.parse_args()

   np.random.seed(args.seed)
   os.makedirs(args.wdir, exist_ok=True)

   N = args.N

   # parse instruction sequence
   if args.I is None:
      # no numbers: NxN identity multiply
      instr_seq = [N, N, N, 0]
      test_type = "identity"
   else:
      try:
         parts = [int(x.strip()) for x in args.I.split(',')]
      except ValueError:
         print(f"ERROR: Invalid instruction format. Expected comma-separated integers, got: {args.I}")
         exit(1)
      
      parts_no_zero = [p for p in parts if p != 0] # remove trailing zeros for figuring out test type
      if len(parts_no_zero) == 0:
         # no numbers: NxN identity multiply
         instr_seq = [N, N, N, 0]
         test_type = "identity"
      elif len(parts_no_zero) == 1:
         # one number: IxI identity multiply (square)
         I = parts_no_zero[0]
         instr_seq = [I, I, I, 0]
         test_type = "identity"
      elif len(parts_no_zero) == 2:
         # two numbers: MxI identity multiply (non-square)
         M, I = parts_no_zero[0], parts_no_zero[1]
         instr_seq = [M, I, I, 0]
         test_type = "identity"
      else:
         # many numbers: MMM chain
         instr_seq = parts
         if not instr_seq or instr_seq[-1] != 0:
            instr_seq.append(0) # ensure terminator 0 is present (user can optionally leave it out)
         test_type = "chain"

   # parse the instruction sequence
   rows = instr_seq[0]  # rows
   dims = []  # [d1, d2, d3, ...]
   for v in instr_seq[1:]:
      if v == 0:
         break
      dims.append(v)

   num_mmms = len(dims) - 1

   # Calculate total MACs: for each MMM, MACs = rows * d_in * d_out
   total_macs = 0
   for mmm_i in range(num_mmms):
      d_in  = dims[mmm_i]
      d_out = dims[mmm_i + 1]
      macs_this_mmm = rows * d_in * d_out
      total_macs += macs_this_mmm

   # build the MMM chain string "(AxB) x (BxC) x (CxD) x (DxE) = (AxE)"
   mmm_chain_parts = [f"({rows}x{dims[0]})"]  # start with first A dimension
   for i in range(len(dims) - 1):
      mmm_chain_parts.append(f"({dims[i]}x{dims[i+1]})")  # add each B dimension
   mmm_chain_str = " x ".join(mmm_chain_parts) + f" = ({rows}x{dims[-1]})"

   # randomly initialize the first Q8.8 matrix A (rows x dims[0])
   first_A = mat_to_q8_8(np.random.uniform(-1.0, 1.0, (rows, dims[0])))
   all_B = []  # concatenated weight matrices in int16 (Q8.8)
   instr_words = list(instr_seq)  # instruction memory words
   current_M = first_A  # running output of the most recent MMM

   # loop through each MMM in the sequence
   for mmm_i in range(num_mmms):
      d_in  = dims[mmm_i]
      d_out = dims[mmm_i + 1]

      # generate identity/random Q8.8 matrix for W (d_in x d_out)
      if test_type == "identity":
         # W is identity
         W_float = np.eye(d_in, d_out, dtype=np.float64)
      else:  # test_type == "chain"
         # W is random
         W_float = np.random.uniform(-1.0, 1.0, (d_in, d_out))
      
      W_q8_8 = mat_to_q8_8(W_float)
      all_B.extend(W_q8_8.flatten().tolist())  # add W to B
      
      # current_M x W = C in 32 bit (Q16.16)
      C_q16_16 = matmul_q8_8(current_M, W_q8_8)

      # convert C back to Q8.8 and put it in current_M for next MMM
      if mmm_i < num_mmms - 1:
         c_q8_8 = np.vectorize(q16_16_to_q8_8)
         current_M = c_q8_8(C_q16_16).astype(np.int16)
      else:  # don't convert back if it's the last MMM (this is our reference output)
         ref_C = C_q16_16

   # write input and reference output files
   a_path = os.path.join(args.wdir, 'mem_a.hex')
   b_path = os.path.join(args.wdir, 'mem_b.hex')
   i_path = os.path.join(args.wdir, 'mem_i.hex')
   r_path = os.path.join(args.wdir, 'ref_out.hex')

   write_hex16(a_path, first_A)
   write_hex16(b_path, np.array(all_B, dtype=np.int16))
   write_hex32(i_path, np.array(instr_words, dtype=np.int32))
   write_hex32(r_path, ref_C.astype(np.int64), add_comments=True)

   n_a   = first_A.size
   n_b   = len(all_B)
   n_i   = len(instr_words)
   n_ref = ref_C.size

   # write sizes so the Makefile can pass exact counts to iverilog
   # eliminates $readmemh "not enough words" warnings
   # also write test type so testbench can print the right message
   params_path = os.path.join(args.wdir, 'params.mk')
   with open(params_path, 'w') as f:
      f.write(f"MEM_A_WORDS  := {n_a}\n")
      f.write(f"MEM_B_WORDS  := {n_b}\n")
      f.write(f"MEM_I_WORDS  := {n_i}\n")
      f.write(f"MEM_REF_WORDS := {n_ref}\n")
      if test_type == "identity":
         test_code = 0  # identity multiply
      else:  # test_type == "chain"
         test_code = 1  # MMM chain
      f.write(f"TEST_TYPE := {test_code}\n")
      if test_type == "identity":
         # identity multiply uses M and I parameters for testbench print instead of the full MMM chain
         M = instr_seq[0]  # M is the dimension of the first matrix
         I = instr_seq[1]  # I is the dimension of the square identity matrix (the second matrix)
      else:  # test_type == "chain"
         # MMM chain doesn't use these at all
         M = 0
         I = 0
      f.write(f"TEST_IDENTITY_M := {M}\n")
      f.write(f"TEST_IDENTITY_I := {I}\n")
      f.write(f"TEST_MAC_TOTAL := {total_macs}\n")
      f.write(f"TEST_MMM_TOTAL := {num_mmms}\n")
      f.write(f"TEST_MMM_CHAIN := {mmm_chain_str}\n")

   print(f"\nWritten to {args.wdir}:")
   print(f"  mem_a.hex    ({n_a} words)")
   print(f"  mem_b.hex    ({n_b} words)")
   print(f"  mem_i.hex    ({n_i} words)")
   print(f"  ref_out.hex  ({n_ref} words)")
   print(f"  params.mk    (configuration parameters for instruction sequence)")
   print(f"  sim_n<N>/    (output directory for each NxN systolic array simulation)")

if __name__ == '__main__':
   main()
