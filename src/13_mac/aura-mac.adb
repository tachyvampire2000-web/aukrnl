--  AURA Kernel — MAC (Biba + CIFC)
--  Пп.33-35 закрыты.  Нет зависимости от Aura.Thread.
--  SPDX-License-Identifier: GPL-2.0-only

with System;

package body Aura.Mac is

   use type Interfaces.Unsigned_64;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_8;

   --  ────────────────── Кольцевой буфер аудита (п.34) ──────────────────────

   Audit_Ring  : Audit_Ring_Array := [others => <>];
   Audit_Head  : Natural := 1;
   Audit_Count : Natural := 0;

   protected Audit_Lock is
      pragma Interrupt_Priority (System.Interrupt_Priority'Last);
      procedure Write (Rec : Audit_Record);
      procedure Drain (Out_Ring : out Audit_Ring_Array; Count : out Natural);
   end Audit_Lock;

   protected body Audit_Lock is
      procedure Write (Rec : Audit_Record) is
      begin
         Audit_Ring (Audit_Head) := Rec;
         Audit_Head  := (Audit_Head mod Audit_Ring_Size) + 1;
         if Audit_Count < Audit_Ring_Size then
            Audit_Count := Audit_Count + 1;
         end if;
      end Write;

      procedure Drain (Out_Ring : out Audit_Ring_Array; Count : out Natural) is
      begin
         Out_Ring    := Audit_Ring;
         Count       := Audit_Count;
         Audit_Ring  := [others => <>];
         Audit_Head  := 1;
         Audit_Count := 0;
      end Drain;
   end Audit_Lock;

   procedure Audit_Channel
     (Subject   : Integrity_Level;
      Object_Lv : Integrity_Level;
      Op        : Mac_Op;
      Allowed   : Boolean)
   is
   begin
      Audit_Lock.Write ((Subject   => Subject,
                         Object_Lv => Object_Lv,
                         Op        => Op,
                         Allowed   => Allowed,
                         Tick      => 0));
   end Audit_Channel;

   procedure Audit_Drain
     (Out_Ring : out Audit_Ring_Array; Count : out Natural)
   is
   begin
      Audit_Lock.Drain (Out_Ring, Count);
   end Audit_Drain;

   --  ──────────────────────────── Biba ──────────────────────────────────────

   --  Biba: субъект читает только объекты уровня ≤ своего (no read-up).
   function Mac_Check_Read
     (Subject   : Integrity_Level;
      Object_Lv : Integrity_Level) return Mac_Decision
   is
      Allowed : constant Boolean := Object_Lv <= Subject;
   begin
      Audit_Channel (Subject, Object_Lv, Mac_Read, Allowed);
      return (if Allowed then Mac_Permit else Mac_Deny);
   end Mac_Check_Read;

   --  Biba: субъект пишет только в объекты уровня ≥ своего (no write-down).
   function Mac_Check_Write
     (Subject   : Integrity_Level;
      Object_Lv : Integrity_Level) return Mac_Decision
   is
      Allowed : constant Boolean := Subject <= Object_Lv;
   begin
      Audit_Channel (Subject, Object_Lv, Mac_Write, Allowed);
      return (if Allowed then Mac_Permit else Mac_Deny);
   end Mac_Check_Write;

   --  IPC = запись в сторону получателя (п.33, вызывается из Channel_Send).
   function Mac_Check_Ipc
     (Sender_Level   : Integrity_Level;
      Receiver_Level : Integrity_Level) return Mac_Decision
   is
   begin
      return Mac_Check_Write (Sender_Level, Receiver_Level);
   end Mac_Check_Ipc;

   --  ────────────────────────── CIFC ────────────────────────────────────────

   procedure Propagate_Taint
     (Taint : in out Causal_Taint;
      Label : Mandatory_Label)
   is
   begin
      Taint.Tainted    := True;
      if Label.Level > Taint.Taint_Level then
         Taint.Taint_Level := Label.Level;
      end if;
      Taint.Categories := Taint.Categories or Label.Categories;
   end Propagate_Taint;

   function Check_Flow
     (Taint  : Causal_Taint;
      Target : Mandatory_Label) return Kernel_Error
   is
   begin
      if not Taint.Tainted then
         return Ok;
      end if;
      if Taint.Taint_Level > Target.Level then
         return Write_Down_Violation;
      end if;
      return Ok;
   end Check_Flow;

end Aura.Mac;
