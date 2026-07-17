--  AURA — Fault-Delegation Subsystem implementation
--  SPDX-License-Identifier: GPL-2.0-only

with System;
with Ada.Unchecked_Conversion;
with Aura.Hal;
with Aura.Sched;
with Aura.Vspace;

package body Aura.Fault is

   use type System.Address;
   use type Aura.Thread.Thread_Access;
   use type Aura.Thread.V_Space_Ref;
   use type Aura.Vspace.V_Space_Ref;

   function Check_Valid (C : Fault_Endpoint_Write_Ref) return Kernel_Error is
   begin
      if C.Object = null then
         return Bad_Cap;
      else
         return Ok;
      end if;
   end Check_Valid;

   function Check_Valid (C : Thread_Manage_Ref) return Kernel_Error is
   begin
      if C.Object = null then
         return Bad_Cap;
      else
         return Ok;
      end if;
   end Check_Valid;

   function Downgrade (C : Integer) return Xpc_Endpoint_Weak_Ref is (null);

   procedure Plat_Map_Segment
     (Root : Interfaces.Unsigned_64; Va, Pa, Size : Interfaces.Unsigned_64;
      Flags : Interfaces.Unsigned_32; Status : out Kernel_Error) is
   begin
      Aura.Hal.Hal_Iommu_Map (Root, Va, Pa, Size, Flags, Status);
   end Plat_Map_Segment;

   procedure Sched_Resume (Th : in out Thread) is
   begin
      Th.State := Aura.Thread.Ready;
      Aura.Sched.Sched_Add_Thread (0, Th'Unrestricted_Access);
   end Sched_Resume;

   procedure Thread_Set_Fault_Handler
     (Th       : in out Thread;
      Endpoint : Fault_Endpoint_Write_Ref;
      Status   : out Kernel_Error)
   is
   begin
      Status := Check_Valid (Endpoint);
      if Status /= Ok then
         return;
      end if;
      Th.Fault_Endpoint := Endpoint.Object.all'Address;
      Status := Ok;
   end Thread_Set_Fault_Handler;

   function To_Real_Vspace_Ref is new Ada.Unchecked_Conversion
     (Aura.Thread.V_Space_Ref, Aura.Vspace.V_Space_Ref);

   procedure Thread_Resume
     (Thread_Cap : Thread_Manage_Ref;
      Map_Phys   : Phys_Addr_Option;
      Map_Va     : Interfaces.Unsigned_64;
      Status     : out Kernel_Error)
   is
      Vspace_Root : Interfaces.Unsigned_64 := 0;
      Map_Status  : Kernel_Error;
      Flags       : constant Interfaces.Unsigned_32 := 3;
   begin
      Status := Check_Valid (Thread_Cap);
      if Status /= Ok then
         return;
      end if;

      if Thread_Cap.Object.Exec_Ctx.Bound_Vspace /= null then
         declare
            Real_Vspace : constant Aura.Vspace.V_Space_Ref :=
              To_Real_Vspace_Ref (Thread_Cap.Object.Exec_Ctx.Bound_Vspace);
         begin
            if Real_Vspace /= null then
               Vspace_Root := Real_Vspace.Page_Table_Root;
            end if;
         end;
      end if;

      if Map_Phys.Present then
         --  Платформенный вызов — граница платформы, идентичная
         --  unsafe-блоку Rust-версии.
         Plat_Map_Segment
           (Vspace_Root, Map_Va, Map_Phys.Value, 4096, Flags,
            Map_Status);
         if Map_Status /= Ok then
            Status := Map_Status;
            return;
         end if;
      end if;

      Sched_Resume (Thread_Cap.Object.all);
      Status := Ok;
   end Thread_Resume;

   procedure Dispatch_Fault_To_Userspace
     (Th     : in out Thread;
      Msg    : Fault_Message;
      Status : out Kernel_Error)
   is
      function To_Endpoint is new Ada.Unchecked_Conversion (System.Address, Fault_Endpoint_Access);
      Handler : Fault_Endpoint_Access;
   begin
      if Th.Fault_Endpoint = System.Null_Address then
         Status := User_Fault;
         return;
      end if;

      Handler := To_Endpoint (Th.Fault_Endpoint);
      if Handler = null then
         Status := Bad_Cap;
         return;
      end if;

      -- Route fault, save details in the handler, and transition thread state to Blocked
      Handler.Last_Fault := Msg;
      Th.State := Aura.Thread.Blocked;
      Status := Ok;
   end Dispatch_Fault_To_Userspace;

end Aura.Fault;
