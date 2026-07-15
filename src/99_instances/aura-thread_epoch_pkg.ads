--  AURA Kernel — Library-level Thread Epoch query specification
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Thread;
with Interfaces;

package Aura.Thread_Epoch_Pkg is

   function Thread_Epoch (T : Aura.Thread.Thread) return Interfaces.Unsigned_32 is (T.Header.Epoch);

end Aura.Thread_Epoch_Pkg;
