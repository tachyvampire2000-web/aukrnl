--  AURA Kernel — ELF loader specification
--  П.28 дорожной карты: ELF-загрузчик объявлен и реализован.
--  Поддерживает ELF64 little-endian (EM_X86_64/EM_AARCH64).
--  SPDX-License-Identifier: GPL-2.0-only

with Aura.Vspace;
with Aura.Kernel_Error_Pkg; use Aura.Kernel_Error_Pkg;
with Interfaces;
with System;

package Aura.Elf is

   pragma SPARK_Mode (Off);

   use type Interfaces.Unsigned_64;

   --  Минимально необходимые константы ELF64.
   ELF_MAGIC      : constant Interfaces.Unsigned_32 := 16#7F454C46#;
   ET_EXEC        : constant Interfaces.Unsigned_16 := 2;
   ET_DYN         : constant Interfaces.Unsigned_16 := 3;
   PT_LOAD        : constant Interfaces.Unsigned_32 := 1;
   EM_X86_64      : constant Interfaces.Unsigned_16 := 62;
   EM_AARCH64     : constant Interfaces.Unsigned_16 := 183;
   ELFCLASS64     : constant := 2;
   ELFDATA2LSB    : constant := 1;

   PF_X           : constant := 1;   -- executable
   PF_W           : constant := 2;   -- writable
   PF_R           : constant := 4;   -- readable

   type Elf64_Ehdr is record
      E_Ident     : array (0 .. 15) of Interfaces.Unsigned_8;
      E_Type      : Interfaces.Unsigned_16;
      E_Machine   : Interfaces.Unsigned_16;
      E_Version   : Interfaces.Unsigned_32;
      E_Entry     : Interfaces.Unsigned_64;
      E_Phoff     : Interfaces.Unsigned_64;
      E_Shoff     : Interfaces.Unsigned_64;
      E_Flags     : Interfaces.Unsigned_32;
      E_Ehsize    : Interfaces.Unsigned_16;
      E_Phentsize : Interfaces.Unsigned_16;
      E_Phnum     : Interfaces.Unsigned_16;
      E_Shentsize : Interfaces.Unsigned_16;
      E_Shnum     : Interfaces.Unsigned_16;
      E_Shstrndx  : Interfaces.Unsigned_16;
   end record
     with Convention => C;

   type Elf64_Phdr is record
      P_Type   : Interfaces.Unsigned_32;
      P_Flags  : Interfaces.Unsigned_32;
      P_Offset : Interfaces.Unsigned_64;
      P_Vaddr  : Interfaces.Unsigned_64;
      P_Paddr  : Interfaces.Unsigned_64;
      P_Filesz : Interfaces.Unsigned_64;
      P_Memsz  : Interfaces.Unsigned_64;
      P_Align  : Interfaces.Unsigned_64;
   end record
     with Convention => C;

   --  Загрузить ELF-образ из буфера данных в заданный VSpace.
   --  Image_Data — адрес начала образа в памяти ядра (уже прочитан).
   --  Image_Size — размер образа в байтах.
   --  Vspace     — VSpace процесса, в который происходит отображение.
   --  Entry_Point — точка входа для boot-потока процесса.
   procedure Load_Elf64
     (Image_Data  : System.Address;
      Image_Size  : Interfaces.Unsigned_64;
      Vspace      : Aura.Vspace.V_Space_Ref;
      Entry_Point : out Interfaces.Unsigned_64;
      Status      : out Kernel_Error);

   --  Проверить заголовок без загрузки.
   function Is_Valid_Elf64 (Image_Data : System.Address;
                             Image_Size : Interfaces.Unsigned_64) return Boolean;

end Aura.Elf;
