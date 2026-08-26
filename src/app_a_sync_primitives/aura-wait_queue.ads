--  AURA — Wait_Queue: очередь ожидания с реальным хранением потоков.
--
--  Пп.8-9 дорожной карты закрыты:
--   - Instance хранит адреса ожидающих потоков, а не только счётчик.
--   - Wake_All_With_Signal реально пробуждает каждый поток через
--     глобальный callback Wake_Proc, установленный планировщиком.
--   - Prepare_With_Token принимает Token и сохраняет его для адресной
--     доставки через Wake_With_Token.
--  SPDX-License-Identifier: GPL-2.0-only

with Interfaces;
with System;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;

package Aura.Wait_Queue is

   pragma SPARK_Mode (Off);

   Wait_Queue_Max_Waiters : constant := 64;

   --  Токен ожидания — идентифицирует конкретный waiter для адресной
   --  доставки (п.9 дорожной карты).
   type Wait_Token is record
      Id : Interfaces.Unsigned_64 := 0;
   end record;

   --  Адрес потока (System.Address) — избегает циклической зависимости
   --  с Aura.Thread.
   type Thread_Handle is new System.Address;
   Null_Thread_Handle : constant Thread_Handle :=
     Thread_Handle (System.Null_Address);

   type Token_Array is
     array (1 .. Wait_Queue_Max_Waiters) of Interfaces.Unsigned_64;
   type Handle_Array is
     array (1 .. Wait_Queue_Max_Waiters) of Thread_Handle;

   type Instance is tagged record
      Waiters      : aliased Natural := 0;
      Signal       : aliased Interfaces.Unsigned_64 := 0;
      --  Адреса ожидающих потоков (п.8 дорожной карты).
      Thread_Addrs : Handle_Array  := [others => Null_Thread_Handle];
      --  Токены для адресной доставки (п.9 дорожной карты).
      Tokens       : Token_Array   := [others => 0];
   end record;

   --  Глобальный callback пробуждения, устанавливается планировщиком при
   --  инициализации.  Принимает адрес потока, переводит его в Ready и
   --  добавляет в run-queue.
   type Wake_Proc_T is access procedure (Th : Thread_Handle);
   Wake_Proc : Wake_Proc_T := null;

   --  Зарегистрироваться как waiter (без токена, без адреса потока —
   --  обратная совместимость с тестами).
   procedure Prepare (Self : in out Instance; Status : out Kernel_Error);

   --  Зарегистрироваться как waiter с адресом потока (п.8).
   procedure Prepare_Thread
     (Self   : in out Instance;
      Thread : Thread_Handle;
      Status : out Kernel_Error);

   --  Зарегистрироваться с токеном для адресной доставки (п.9).
   procedure Prepare_With_Token
     (Self   : in out Instance;
      Token  : Wait_Token;
      Status : out Kernel_Error);

   --  Снять регистрацию текущего слота.
   procedure Cancel (Self : in out Instance);

   --  Снять регистрацию конкретного потока.
   procedure Cancel_Thread (Self : in out Instance; Thread : Thread_Handle);

   --  Снимок числа ожидающих без блокировки.
   function Waiter_Count_Snapshot (Self : Instance) return Natural;

   --  Разбудить всех ожидающих (п.8): инкрементирует Signal и вызывает
   --  Wake_Proc для каждого сохранённого адреса потока.
   procedure Wake_All_With_Signal (Self : in out Instance);

   --  Разбудить только waiter с заданным токеном (п.9).
   procedure Wake_With_Token
     (Self  : in out Instance;
      Token : Wait_Token);

end Aura.Wait_Queue;
