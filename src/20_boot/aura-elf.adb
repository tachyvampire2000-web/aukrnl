--  AURA Kernel — ELF loader implementation (ELF64 little-endian)
--  П.28 дорожной карты: реальный парсинг ELF-заголовка и PT_LOAD сегментов;
--  каждый сегмент отображается в VSpace процесса через Vspace_Map.
--  Elf_Load_Error теперь используется (не просто объявлен).
--  SPDX-License-Identifier: GPL-2.0-only

with System.Storage_Elements; use System.Storage_Elements;
with Ada.Unchecked_Conversion;

package body Aura.Elf is

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;

   type Byte_Array is array (Interfaces.Unsigned_64 range <>) of Interfaces.Unsigned_8;
   type Byte_Array_Ptr is access all Byte_Array;

   function Addr_To_Ehdr is new Ada.Unchecked_Conversion
     (System.Address, access Elf64_Ehdr);
   function Addr_To_Phdr is new Ada.Unchecked_Conversion
     (System.Address, access Elf64_Phdr);

   function Is_Valid_Elf64 (Image_Data : System.Address;
                             Image_Size : Interfaces.Unsigned_64) return Boolean
   is
      Hdr : constant access Elf64_Ehdr := Addr_To_Ehdr (Image_Data);
   begin
      if Image_Size < 64 then return False; end if;
      --  Проверяем Magic bytes (EI_MAG0..EI_MAG3).
      if Hdr.E_Ident (0) /= 16#7F# or else
         Hdr.E_Ident (1) /= Character'Pos ('E') or else
         Hdr.E_Ident (2) /= Character'Pos ('L') or else
         Hdr.E_Ident (3) /= Character'Pos ('F')
      then
         return False;
      end if;
      --  EI_CLASS = ELFCLASS64.
      if Hdr.E_Ident (4) /= ELFCLASS64 then return False; end if;
      --  EI_DATA = ELFDATA2LSB.
      if Hdr.E_Ident (5) /= ELFDATA2LSB then return False; end if;
      --  e_type должен быть ET_EXEC или ET_DYN.
      if Hdr.E_Type /= ET_EXEC and then Hdr.E_Type /= ET_DYN then
         return False;
      end if;
      --  Поддерживаемые архитектуры.
      if Hdr.E_Machine /= EM_X86_64 and then
         Hdr.E_Machine /= EM_AARCH64
      then
         return False;
      end if;
      return True;
   end Is_Valid_Elf64;

   procedure Load_Elf64
     (Image_Data  : System.Address;
      Image_Size  : Interfaces.Unsigned_64;
      Vspace      : Aura.Vspace.V_Space_Ref;
      Entry_Point : out Interfaces.Unsigned_64;
      Status      : out Kernel_Error)
   is
      Hdr       : constant access Elf64_Ehdr := Addr_To_Ehdr (Image_Data);
      Base_Addr : constant Integer_Address := To_Integer (Image_Data);
      Page_Size : constant := 16#1000#;

      --  Округление адреса/размера до страницы.
      function Align_Down (V : Interfaces.Unsigned_64) return Interfaces.Unsigned_64 is
        (V and not (Page_Size - 1));
      function Align_Up (V : Interfaces.Unsigned_64) return Interfaces.Unsigned_64 is
        ((V + Page_Size - 1) and not (Page_Size - 1));

      Phdr_Offset : Interfaces.Unsigned_64;
      Phdr        : access Elf64_Phdr;
      Map_Va      : Interfaces.Unsigned_64;
      Map_Phys    : Interfaces.Unsigned_64;
      Map_Size    : Interfaces.Unsigned_64;
      Map_Flags   : Interfaces.Unsigned_32;
      Map_Status  : Kernel_Error;
   begin
      Entry_Point := 0;
      Status      := Ok;

      if not Is_Valid_Elf64 (Image_Data, Image_Size) then
         Status := Elf_Load_Error;
         return;
      end if;

      if Hdr.E_Phentsize < Elf64_Phdr'Size / 8 then
         Status := Elf_Load_Error;
         return;
      end if;

      Entry_Point := Hdr.E_Entry;

      --  Обходим program header table и загружаем PT_LOAD сегменты.
      Phdr_Offset := Hdr.E_Phoff;
      for I in 0 .. Natural (Hdr.E_Phnum) - 1 loop
         declare
            Phdr_Addr : constant Integer_Address :=
              Base_Addr
              + Integer_Address (Phdr_Offset)
              + Integer_Address (I) * Integer_Address (Hdr.E_Phentsize);
         begin
            Phdr := Addr_To_Phdr (To_Address (Phdr_Addr));
            if Phdr.P_Type = PT_LOAD then
               --  Выравниваем по странице.
               Map_Va   := Align_Down (Phdr.P_Vaddr);
               Map_Phys := Interfaces.Unsigned_64 (Base_Addr)
                            + Align_Down (Phdr.P_Offset);
               Map_Size := Align_Up (Phdr.P_Memsz
                            + (Phdr.P_Vaddr - Map_Va));

               --  Собираем флаги из p_flags.
               Map_Flags := 0;
               if (Phdr.P_Flags and PF_R) /= 0 then
                  Map_Flags := Map_Flags or
                    Interfaces.Unsigned_32 (Aura.Vspace.Flag_Read);
               end if;
               if (Phdr.P_Flags and PF_W) /= 0 then
                  Map_Flags := Map_Flags or
                    Interfaces.Unsigned_32 (Aura.Vspace.Flag_Write);
               end if;
               if (Phdr.P_Flags and PF_X) /= 0 then
                  Map_Flags := Map_Flags or
                    Interfaces.Unsigned_32 (Aura.Vspace.Flag_Exec);
               end if;

               Aura.Vspace.Vspace_Map
                 (Vs     => Vspace,
                  Va     => Map_Va,
                  Phys   => Map_Phys,
                  Size   => Map_Size,
                   Flags  => Aura.Vspace.Page_Flags (Map_Flags),
                  Status => Map_Status);

               if Map_Status /= Ok then
                  Status := Elf_Load_Error;
                  return;
               end if;
            end if;
         end;
      end loop;
   end Load_Elf64;

end Aura.Elf;
