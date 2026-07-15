--  AURA Kernel — aura-channel.ads
--  SPDX-License-Identifier: GPL-2.0-only


with Interfaces;
with Ada.Containers.Bounded_Vectors;
with Aura.Object;           use Aura.Object;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Aura.Rights;           use Aura.Rights;
with Aura.Ticket_Lock;
with Aura.Wait_Queue;
with Aura.Notification;

package Aura.Channel is

   pragma SPARK_Mode (Off);

   use type Interfaces.Unsigned_64;
   use type Ada.Containers.Count_Type;

   --  Option-типы — эквиваленты Option<ErasedCap>, Option<CapId>,
   --  Option<u64> из Rust-версии.
   type Erased_Cap_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Interfaces.Unsigned_64;
         when False => null;
      end case;
   end record;

   type Cap_Id_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Interfaces.Unsigned_64;
         when False => null;
      end case;
   end record;

   type Tick_Option (Present : Boolean := False) is record
      case Present is
         when True  => Value : Interfaces.Unsigned_64;
         when False => null;
      end case;
   end record;

   Channel_Queue_Depth : constant := 64;
   Channel_Msg_Data_Len : constant := 256;

   type Byte_Array_256 is array (0 .. Channel_Msg_Data_Len - 1)
     of Interfaces.Unsigned_8;

   type Channel_Message is record
      Data     : Byte_Array_256;
      Data_Len : Interfaces.Unsigned_32;
      Cap      : Erased_Cap_Option;    --  эквивалент Option<ErasedCap>
      Cause    : Cap_Id_Option;         --  T49: causal chain, эквивалент
                                          --  Option<CapId>
   end record;

   package Channel_Msg_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Channel_Message);

   type Channel_Queue is record
      Msgs : Channel_Msg_Vectors.Vector (Channel_Queue_Depth);
      Wait : Aura.Wait_Queue.Instance;
   end record;

   package Channel_Queue_Locks is new Aura.Ticket_Lock (Channel_Queue);

   type Channel is limited record
      Header  : Object_Header;
      A_To_B  : Channel_Queue_Locks.Instance;
      B_To_A  : Channel_Queue_Locks.Instance;
   end record;

   type Channel_Ref is access all Channel;

   type Channel_Side is (Side_A, Side_B);

   type Channel_Endpoint is limited record
      Header  : Object_Header;
      Channel : Channel_Ref;
      Side    : Channel_Side := Side_A;
   end record;

   type Channel_Endpoint_Access is access all Channel_Endpoint;

   --  Мандаты (рантайм-представление прав — см. §1 порта).
   type Channel_Endpoint_Write_Ref is record
      Object : Channel_Endpoint_Access;
      Rights : Aura.Rights.Mask := Aura.Rights.Write;
   end record;

   type Channel_Endpoint_Read_Ref is record
      Object : Channel_Endpoint_Access;
      Rights : Aura.Rights.Mask := Aura.Rights.Read;
   end record;

   type Notification_Read_Ref is record
      Object : Aura.Notification.Notification_Ref;
      Rights : Aura.Rights.Mask := Aura.Rights.Read;
   end record;

   function Check_Valid
     (Cap : Channel_Endpoint_Write_Ref) return Kernel_Error;
   function Check_Valid
     (Cap : Channel_Endpoint_Read_Ref) return Kernel_Error;
   function Check_Valid (Cap : Notification_Read_Ref) return Kernel_Error;

   procedure Channel_Send
     (Ep     : Channel_Endpoint_Write_Ref;  --  требует Write
      Msg    : Channel_Message;
      Status : out Kernel_Error)
   with Pre => Contains (Ep.Rights, Write);


   procedure Channel_Recv
     (Ep      : Channel_Endpoint_Read_Ref;  --  требует Read
      Timeout : Tick_Option;                 --  эквивалент Option<u64>
      Msg     : out Channel_Message;
      Status  : out Kernel_Error)
   with Pre => Contains (Ep.Rights, Aura.Rights.Read);


   --  T31: ожидать сигнала от любого из набора Notification или
   --  Channel_Endpoint. Возвращает индекс первого сработавшего мандата.
   --  Аналог select()/epoll() на уровне capability-объектов.
   Wait_Any_Max : constant := 64;

   type Wait_Any_Source_Kind is (Notification_Source, Channel_Source);

   type Wait_Any_Source (Kind : Wait_Any_Source_Kind := Notification_Source) is
     record
        case Kind is
           when Notification_Source =>
              Notification_Cap : Notification_Read_Ref;  --  требует Read
           when Channel_Source =>
              Channel_Cap : Channel_Endpoint_Read_Ref;    --  требует Read
        end case;
     end record;

   package Wait_Any_Source_Vectors is new Ada.Containers.Bounded_Vectors
     (Index_Type => Positive, Element_Type => Wait_Any_Source);

   procedure Cap_Wait_Any
     (Sources : Wait_Any_Source_Vectors.Vector;
      Timeout : Tick_Option;
      Index   : out Natural;
      Status  : out Kernel_Error)
   with Pre => Wait_Any_Source_Vectors.Length (Sources) > 0
               and then Wait_Any_Source_Vectors.Length (Sources) <= Wait_Any_Max;


   --  Отдельная, логически не связанная с Cap_Wait_Any функция —
   --  перенесена на своё законное место, а не оставлена в конце раздела,
   --  как в исходном документе (там это, по всей видимости, артефакт
   --  порядка написания, а не намеренная группировка).
   type Task_Force is limited record
      Header           : Object_Header;
      Shared_Budget_Us : aliased Interfaces.Unsigned_64 := 0;
      Shared_Memory_Budget : aliased Interfaces.Unsigned_64 := 0;
      Shared_Io_Budget     : aliased Interfaces.Unsigned_64 := 0;
   end record;

   --  Атомарно списать Ticks из общего бюджета (с насыщением в 0);
   --  True, если бюджет исчерпан.
   function Task_Force_Decrement_Budget
     (Tf : in out Task_Force; Ticks : Interfaces.Unsigned_64) return Boolean;

   --  Атомарно списать Bytes из общего бюджета памяти (с насыщением в 0);
   --  True, если бюджет исчерпан.
   function Task_Force_Decrement_Memory
     (Tf : in out Task_Force; Bytes : Interfaces.Unsigned_64) return Boolean;

   --  Атомарно списать Operations из общего IO бюджета (с насыщением в 0);
   --  True, если бюджет исчерпан.
   function Task_Force_Decrement_Io
     (Tf : in out Task_Force; Operations : Interfaces.Unsigned_64) return Boolean;

end Aura.Channel;
