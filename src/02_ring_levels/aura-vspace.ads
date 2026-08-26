--  AURA Kernel — Virtual Address Space (VSpace)
--  Пп.22,47 дорожной карты:
--  22: Vspace_Map/Unmap/Query_Flags/Remap_Flags реализованы.
--  47: Vspace_Destroy освобождает ресурсы процесса.
--
--  Все Vspace_* операции объявлены здесь; тела — в aura-vspace.adb.
--  На референс-платформе (без MMU) они — минимальные заглушки,
--  задокументированные как преднамеренные (см. HAL-правило).
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Object; use Aura.Object;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with System;
with Interfaces;

package Aura.Vspace is

   pragma SPARK_Mode (Off);

   --  Флаги страниц (совместимы с x86 PTE и AArch64 PTE).
   type Page_Flags is new Interfaces.Unsigned_64;

   Page_Present    : constant Page_Flags := 16#001#;
   Page_Writable   : constant Page_Flags := 16#002#;
   Page_User       : constant Page_Flags := 16#004#;
   Page_No_Execute : constant Page_Flags := 16#8000_0000_0000_0000#;
   Page_None       : constant Page_Flags := 0;
   Flag_Read  : constant Page_Flags := Page_Present;
   Flag_Write : constant Page_Flags := Page_Writable;
   Flag_Exec  : constant Page_Flags := Page_User;

   --  Корень таблицы страниц + стандартный Object_Header.
   type V_Space is limited record
      Header           : Object_Header;
      Page_Table_Root  : Interfaces.Unsigned_64 := 0;
      Migrated_Threads : System.Address := System.Null_Address;
   end record;

   type V_Space_Ref is access all V_Space;

   type Process_Context is limited record
      Vspace : V_Space_Ref;
   end record;

   type Process_Context_Ref is access all Process_Context;
   type Process_Context_Weak_Ref is access all Process_Context;

   --  ────────────────────── VSpace lifecycle ────────────────────────────────

   --  Создать пустое адресное пространство (аллоцирует объект).
   procedure Vspace_Create
     (Vs     : out V_Space_Ref;
      Status : out Kernel_Error);

   --  Уничтожить адресное пространство и освободить ресурсы (п.47).
   procedure Vspace_Destroy
     (Vs : in out V_Space_Ref);

   --  ────────────────────── Mapping operations ──────────────────────────────

   --  Отобразить физический диапазон [Pa .. Pa+Size) → [Va .. Va+Size).
   procedure Vspace_Map
     (Vs     : V_Space_Ref;
      Va     : Interfaces.Unsigned_64;
       Phys   : Interfaces.Unsigned_64;
      Size   : Interfaces.Unsigned_64;
      Flags  : Page_Flags;
      Status : out Kernel_Error);

   --  Снять отображение [Va .. Va+Size).
   procedure Vspace_Unmap
     (Vs     : V_Space_Ref;
      Va     : Interfaces.Unsigned_64;
      Size   : Interfaces.Unsigned_64;
      Status : out Kernel_Error);

   --  Скопировать отображения из шаблонного VSpace в Vs (COW-образ).
   procedure Vspace_Map_Template
     (Vs       : V_Space_Ref;
      Template : V_Space;
      Status   : out Kernel_Error);

   --  Прочитать флаги страницы, содержащей Va.
   procedure Vspace_Query_Flags
     (Vs     : V_Space_Ref;
      Va     : Interfaces.Unsigned_64;
      Flags  : out Page_Flags;
      Status : out Kernel_Error);

   --  Заменить флаги страниц в диапазоне [Va .. Va+Size).
   procedure Vspace_Remap_Flags
     (Vs        : V_Space_Ref;
      Va        : Interfaces.Unsigned_64;
      Size      : Interfaces.Unsigned_64;
       Flags     : Page_Flags;
      Status    : out Kernel_Error);

end Aura.Vspace;
