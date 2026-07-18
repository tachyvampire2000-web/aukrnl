--  AURA — Fault-Delegation Subsystem implementation
--  SPDX-License-Identifier: GPL-2.0-only

with System;
with System.Storage_Elements;
with Ada.Unchecked_Conversion;
with Aura.Hal;
with Aura.Sched;
with Aura.Vspace;

package body Aura.Fault is

   use type System.Address;
   use type Aura.Thread.Thread_Access;
   use type Aura.Thread.V_Space_Ref;
   use type Aura.Vspace.V_Space_Ref;
   use type Aura.Thread.Fault_Endpoint_Weak_Ref;

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

   function Downgrade (C : Integer) return Xpc_Endpoint_Weak_Ref is
      Result : Xpc_Endpoint_Weak_Ref;
      pragma Unreferenced (C);
   begin
      Result := new Xpc_Endpoint_Inner;
      Result.Allowed := True;
      Result.Rights  := Aura.Rights.Read;
      return Result;
   end Downgrade;

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
      declare
         function To_Header_Ref is new Ada.Unchecked_Conversion
           (Fault_Endpoint_Access, Aura.Thread.Fault_Endpoint_Weak_Ref);
      begin
         Th.Fault_Endpoint := To_Header_Ref (Endpoint.Object);
      end;
      Status := Ok;
   end Thread_Set_Fault_Handler;

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
         Vspace_Root := Thread_Cap.Object.Exec_Ctx.Bound_Vspace.Page_Table_Root;
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
      Handler : Fault_Endpoint_Access;
   begin
      if Th.Fault_Endpoint = null then
         Status := User_Fault;
         return;
      end if;

      declare
         use type System.Storage_Elements.Integer_Address;
         Header_Addr : constant System.Storage_Elements.Integer_Address :=
           System.Storage_Elements.To_Integer (Th.Fault_Endpoint.all'Address);
         Base_Addr   : constant System.Storage_Elements.Integer_Address := Header_Addr;
         function To_Endpoint is new Ada.Unchecked_Conversion
           (System.Storage_Elements.Integer_Address, Fault_Endpoint_Access);
      begin
         Handler := To_Endpoint (Base_Addr);
      end;

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
