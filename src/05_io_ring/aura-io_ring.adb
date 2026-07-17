--  AURA Kernel — aura-io_ring.adb
--  SPDX-License-Identifier: GPL-2.0-only


with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Ada.Unchecked_Deallocation;
with Aura.Sched;

package body Aura.Io_Ring is

   use type Interfaces.Unsigned_32;

   procedure Force_Xpc_Reply_With_Error (T : in out Aura.Thread.Thread; E : Kernel_Error) is
      pragma Unreferenced (E);
   begin
      T.State := Aura.Thread.Ready;
      Aura.Sched.Sched_Add_Thread (0, T'Unrestricted_Access);
   end Force_Xpc_Reply_With_Error;

   procedure Object_Destroy_Vspace (Victim : in out V_Space)
   is
      Ptr    : Thread_Access := Victim.Migrated_Threads;
      Thread : Thread_Access;
   begin
      while Ptr /= null loop
         Thread := Ptr;
         Force_Xpc_Reply_With_Error (Thread.all, Host_Vspace_Destroyed);
         Ptr := Thread_Access (Thread.Migration_List_Next);
      end loop;
      Victim.Migrated_Threads := null;
   end Object_Destroy_Vspace;

   procedure Execute_Step (Step : Io_Ring_Sqe_Inner; Res : out Io_Batch_Result_Step) is
   begin
      if Step.Cap_Index = 0 then
         Res.Status := Bad_Cap;
         Res.New_Value := Step;
         return;
      end if;

      case Step.Op_Code is
         when Read | Write | Map_Memory | Unmap_Memory | Attr_Get | Attr_Set | Attr_Watch | Mount | Device_Query =>
            Res.Status := Ok;
            Res.New_Value := Step;
         when others =>
            Res.Status := Not_Supported;
            Res.New_Value := Step;
      end case;
   end Execute_Step;

   function Io_Batch_Compile (Sqes : Io_Ring_Sqe_Array) return Io_Batch is
      Batch : Io_Batch;
      Sqe_Inner : Io_Ring_Sqe_Inner_Access;
   begin
      Batch.Count := 0;
      for I in Sqes'Range loop
         exit when Batch.Count = Io_Batch_Max_Ops;
         Batch.Count := Batch.Count + 1;
         Batch.Steps (Batch.Count) := Sqes (I);

         -- Allocate a new non-volatile Io_Ring_Sqe_Inner representing the target
         Sqe_Inner := new Io_Ring_Sqe_Inner'(Sqes (I));
         Batch_Target_Vectors.Append (Batch.Targets, Sqe_Inner);
      end loop;
      return Batch;
   end Io_Batch_Compile;

   function Io_Batch_Execute (Ring : in out Io_Ring; Batch : in out Io_Batch) return Io_Batch_Result is
      pragma Unreferenced (Ring);
      Result : Io_Batch_Result;
      Backup : Io_Batch_Step_Array;
   begin
      -- Backup current states for transactional recovery/rollback
      for I in 1 .. Batch.Count loop
         Backup (I) := Batch_Target_Vectors.Element (Batch.Targets, I).all;
         Result.Step_Results (I).Status := Ok;
      end loop;

      -- Execute steps sequentially
      for I in 1 .. Batch.Count loop
         Execute_Step (Batch.Steps (I), Result.Step_Results (I));

         if Result.Step_Results (I).Status /= Ok then
            -- Rollback phase: Abort all changes and restore original values!
            for J in 1 .. Batch.Count loop
               Batch_Target_Vectors.Element (Batch.Targets, J).all := Backup (J);
            end loop;
            Result.Failed_At := I;
            return Result;
         else
            -- Commit step value
            Batch_Target_Vectors.Element (Batch.Targets, I).all := Result.Step_Results (I).New_Value;
         end if;
      end loop;

      Result.Failed_At := 0; -- 0 represents success
      return Result;
   end Io_Batch_Execute;

   function Io_Batch_Submit (Ring : in out Io_Ring; Sqes : Io_Ring_Sqe_Array) return Io_Batch_Result is
      Batch : Io_Batch := Io_Batch_Compile (Sqes);
      Res   : Io_Batch_Result;
   begin
      Res := Io_Batch_Execute (Ring, Batch);
      Io_Batch_Free (Batch);
      return Res;
   end Io_Batch_Submit;

   procedure Io_Batch_Free (Batch : in out Io_Batch) is
      procedure Free_Sqe is new Ada.Unchecked_Deallocation (Io_Ring_Sqe_Inner, Io_Ring_Sqe_Inner_Access);
      Sqe_Inner : Io_Ring_Sqe_Inner_Access;
   begin
      for I in 1 .. Batch.Count loop
         Sqe_Inner := Batch_Target_Vectors.Element (Batch.Targets, I);
         Free_Sqe (Sqe_Inner);
      end loop;
      Batch.Count := 0;
      Batch_Target_Vectors.Clear (Batch.Targets);
   end Io_Batch_Free;

   function Io_Template_Execute
     (Ring     : in out Io_Ring;
      Template : Io_Template_Id) return Io_Batch_Result
   is
      Sqes : Io_Ring_Sqe_Array (1 .. 2);
   begin
      case Template is
         when Read_Then_Write =>
            Sqes (1) := (Op_Code => Read, Cap_Index => 1);
            Sqes (2) := (Op_Code => Write, Cap_Index => 2);
         when Map_Then_Set_Attr =>
            Sqes (1) := (Op_Code => Map_Memory, Cap_Index => 3);
            Sqes (2) := (Op_Code => Attr_Set, Cap_Index => 4);
      end case;

      return Io_Batch_Submit (Ring, Sqes);
   end Io_Template_Execute;

end Aura.Io_Ring;
