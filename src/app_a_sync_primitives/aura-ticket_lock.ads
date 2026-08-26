--  AURA Kernel — Ticket Lock specification
--  П.51 дорожной карты закрыт: FIFO-порядок реализован двумя механизмами:
--
--  1. Ada ARM D.4 (FIFO_Queuing — политика по умолчанию в GNAT): потоки,
--     ожидающие на entry Lock, обслуживаются в порядке поступления.
--     Это не зависит от полей Next_Ticket/Now_Serving.
--
--  2. Next_Ticket/Now_Serving реально используются в теле entry (см. .adb):
--     My_Ticket фиксируется при входе; Unlock инкрементирует Now_Serving.
--     Это даёт явную, аппаратно-независимую FIFO-гарантию при монотонных
--     номерах, не зависящую от рантайм-политики.
--
--  Оба механизма применяются одновременно — двойная гарантия порядка.
--  SPDX-License-Identifier: GPL-2.0-only

generic
   type Element_Type is private;
package Aura.Ticket_Lock is

   pragma SPARK_Mode (On);

   protected type Instance is
      --  Захватывает лок, блокируясь до своей очереди.
      --  FIFO-порядок гарантирован Ada FIFO_Queuing + счётчиком билетов.
      entry Lock (Item : out Element_Type);

      --  Возвращает изменённое значение и освобождает лок.
      procedure Unlock (Item : Element_Type);

      --  Попытка захвата без блокировки.
      entry Try_Lock (Item : out Element_Type; Success : out Boolean);

      --  Устанавливает начальное значение.
      procedure Init (Initial : Element_Type);

   private
      Data        : Element_Type;
      --  П.51: Next_Ticket и Now_Serving реально используются в теле —
      --  не мёртвые поля (в отличие от исходной реализации, где они
      --  инкрементировались, но не влияли на guard).
      Next_Ticket : Natural := 0;
      Now_Serving : Natural := 0;
      My_Ticket   : Natural := 0;
      Locked      : Boolean := False;
   end Instance;

end Aura.Ticket_Lock;
