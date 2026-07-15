--  AURA Kernel — Library-level Thread Capability Instantiation specification
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Capability;
with Aura.Thread;
with Aura.Thread_Epoch_Pkg;

package Aura.Thread_Capability is new Aura.Capability (Aura.Thread.Thread, Aura.Thread_Epoch_Pkg.Thread_Epoch);
