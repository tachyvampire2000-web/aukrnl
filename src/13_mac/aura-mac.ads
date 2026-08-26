--  AURA Kernel — MAC specification
--  Пп.33-35 дорожной карты:
--  33. Mac_Check_Ipc вызывается из Channel_Send.
--  34. Audit_Channel — реальный кольцевой буфер 256 записей.
--  35. Реализована Biba Strict Integrity Policy.
--
--  Backward compatibility: Causal_Taint / Mandatory_Label /
--  Propagate_Taint / Check_Flow сохранены — selftest использует CIFC.
--
--  Циклической зависимости нет: Mac НЕ зависит от Thread.
--  Mac_Get_Level / Mac_Set_Level убраны — вызывающий код обращается
--  к Thread.Mac_Level напрямую.
--  SPDX-License-Identifier: GPL-2.0-only

with Interfaces;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;

package Aura.Mac is

   pragma SPARK_Mode (Off);

   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_8;

   --  ─────────────────────────── Biba Integrity ────────────────────────────

   type Integrity_Level is new Interfaces.Unsigned_32;

   Integrity_Untrusted : constant Integrity_Level := 0;
   Integrity_Kernel    : constant Integrity_Level := 255;

   type Mac_Decision is (Mac_Permit, Mac_Deny);

   type Mac_Op is (Mac_Read, Mac_Write, Mac_Ipc);

   type Audit_Record is record
      Subject   : Integrity_Level := 0;
      Object_Lv : Integrity_Level := 0;
      Op        : Mac_Op := Mac_Read;
      Allowed   : Boolean := False;
      Tick      : Interfaces.Unsigned_64 := 0;
   end record;

   Audit_Ring_Size : constant := 256;
   type Audit_Ring_Array is array (1 .. Audit_Ring_Size) of Audit_Record;

   --  Biba read-up check: объект должен быть не выше субъекта.
   function Mac_Check_Read
     (Subject   : Integrity_Level;
      Object_Lv : Integrity_Level) return Mac_Decision;

   --  Biba write-down check: субъект должен быть не выше объекта.
   function Mac_Check_Write
     (Subject   : Integrity_Level;
      Object_Lv : Integrity_Level) return Mac_Decision;

   --  IPC-check (п.33): вызывается из Channel_Send.
   function Mac_Check_Ipc
     (Sender_Level   : Integrity_Level;
      Receiver_Level : Integrity_Level) return Mac_Decision;

   --  Реальный аудит-канал (п.34).
   procedure Audit_Channel
     (Subject   : Integrity_Level;
      Object_Lv : Integrity_Level;
      Op        : Mac_Op;
      Allowed   : Boolean);

   procedure Audit_Drain
     (Out_Ring : out Audit_Ring_Array;
      Count    : out Natural);

   --  ──────────────── CIFC (Causal Information Flow Control) ───────────────
   --  Сохранены для selftest-а: Test_Conceptual_Extensions использует
   --  Causal_Taint, Mandatory_Label, Propagate_Taint, Check_Flow.

   type Mandatory_Label is record
      Level      : Interfaces.Unsigned_8 := 0;
      Categories : Interfaces.Unsigned_8 := 0;
   end record;

   type Causal_Taint is record
      Tainted     : Boolean := False;
      Taint_Level : Interfaces.Unsigned_8 := 0;
      Categories  : Interfaces.Unsigned_8 := 0;
   end record;

   --  Пометить Taint меткой Label (принимаем наибольший уровень).
   procedure Propagate_Taint
     (Taint : in out Causal_Taint;
      Label : Mandatory_Label);

   --  Проверить допустимость записи Taint-ованных данных в объект Target.
   --  Write_Down_Violation если Taint.Taint_Level > Target.Level.
   function Check_Flow
     (Taint  : Causal_Taint;
      Target : Mandatory_Label) return Kernel_Error;

end Aura.Mac;
