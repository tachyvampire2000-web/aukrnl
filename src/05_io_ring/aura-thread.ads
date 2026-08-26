--  AURA Kernel — Thread type + lifecycle API
--  Пп.27,38,60 дорожной карты:
--  27: Thread_Create и Thread_Destroy объявлены и реализованы.
--  38: Mac_Level (Biba) добавлен в Thread.
--  60: Thread_Destroy зачищает снимки контекста (Flip_Cell).
--
--  Backward compat для selftest-а: поле Taint (Causal_Taint) сохранено
--  рядом с Mac_Level — тест на строках 517/804/832/893 использует
--  ``Taint => <>``.
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Object; use Aura.Object;
with Aura.Flip_Cell;
with Aura.Ring;
with Aura.Mac;
with Aura.Vspace;
with System.Storage_Elements;
with System;
with Interfaces;

package Aura.Thread is

   pragma SPARK_Mode (Off);

   type Register_File is array (1 .. 16) of Interfaces.Unsigned_64;
   type Fpu_State_Area is array (1 .. 512) of Interfaces.Unsigned_8;
   type V_Space_Ref is access all Aura.Vspace.V_Space;
   type V_Space_Weak_Ref is access all Aura.Vspace.V_Space;

   type Sched_Ctx is limited record
      Header        : Object_Header;
      Budget_Us     : Interfaces.Unsigned_64;
      Period_Us     : Interfaces.Unsigned_64;
      Remaining_Us  : aliased Interfaces.Unsigned_64;
      Deadline_Tick : aliased Interfaces.Unsigned_64 := 0;
      Numa_Node     : aliased Interfaces.Unsigned_32 := 0;
      Cpu_Affinity  : aliased Interfaces.Unsigned_64 := 1;
   end record
     with Volatile;

   type Sched_Ctx_Access is access all Sched_Ctx;
   subtype Sched_Ctx_Manage_Ref is Sched_Ctx_Access;

   type Thread;
   type Thread_Access is access all Thread;

   type Fault_Endpoint_Weak_Ref is access all Aura.Object.Object_Header;

   type Execution_Context is record
      Registers    : Register_File;
      Stack_Ptr    : System.Storage_Elements.Integer_Address;
      Bound_Vspace : V_Space_Ref;
      Fpu_State    : Fpu_State_Area;
   end record;

   type Execution_Context_Snap is record
      Registers        : Register_File;
      Stack_Ptr        : System.Storage_Elements.Integer_Address;
      Vspace_Phys_Root : Interfaces.Unsigned_64;
      Vspace_Ref       : V_Space_Weak_Ref;
      Fpu_State        : Fpu_State_Area;
   end record;

   package Snap_Cells is new Aura.Flip_Cell (Execution_Context_Snap);

   type Thread_State is
     (Created, Ready, Running, Blocked, Suspended, Zombie);
   for Thread_State use
     (Created => 0, Ready => 1, Running => 2, Blocked => 3,
      Suspended => 4, Zombie => 5);

   type Thread is limited record
      Header              : Object_Header;
      Exec_Ctx            : Execution_Context;
      Exec_Snapshot       : Snap_Cells.Instance;
      Snapshot_Valid      : aliased Boolean := False;
      Active_Sched_Ctx    : Sched_Ctx_Access;
      Own_Sched_Ctx       : aliased Sched_Ctx;
      Migration_List_Next : Thread_Access;
      --  Fault handler: слабая ссылка на Object_Header первого поля
      --  любого объекта ядра — совместима с любым kernel object.
      Fault_Endpoint      : Fault_Endpoint_Weak_Ref;
      Last_Syscall_Tick   : aliased Interfaces.Unsigned_64;
      Ring_Level          : Aura.Ring.Ring_Level;
      State               : aliased Thread_State;
      --  П.38: MAC уровень целостности (Biba).
      Mac_Level           : aliased Aura.Mac.Integrity_Level := 0;
      --  Backward compat для selftest-а (строки 517/804/832/893):
      --  CIFC-метка замаранности.  Живёт рядом с Mac_Level.
      Taint               : aliased Aura.Mac.Causal_Taint;
   end record
     with Volatile;

   procedure Sched_Ctx_Create
     (Budget_Us, Period_Us : Interfaces.Unsigned_64;
      Result               : out Sched_Ctx_Manage_Ref);

   procedure Sched_Ctx_Destroy
     (Ctx : in out Sched_Ctx_Manage_Ref);

   --  П.27: Thread_Create создаёт поток с CBS-контекстом.
   --  П.60: Thread_Destroy зачищает Flip_Cell снимки.
   procedure Thread_Create
     (Ring_Level : Aura.Ring.Ring_Level;
      Budget_Us  : Interfaces.Unsigned_64;
      Period_Us  : Interfaces.Unsigned_64;
      Result     : out Thread_Access);

   procedure Thread_Destroy
     (Th : in out Thread_Access);

end Aura.Thread;
