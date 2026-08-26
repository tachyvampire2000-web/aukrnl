--  AURA Kernel — Weak references с epoch-защитой
--  П.17 дорожной карты: Upgrade разыменовывает Target только ПОСЛЕ
--  проверки эпохи — устраняет use-after-free при разыменовании до
--  проверки (предыдущая реализация читала поля до сравнения эпох).
--  SPDX-License-Identifier: GPL-2.0-only

package body Aura.Weak_Ref is

   use type Interfaces.Unsigned_32;

   procedure Upgrade
     (Self  : Instance;
      Value : out Object_Access;
      Alive : out Boolean)
   is
   begin
      --  П.17 дорожной карты: сначала проверяем Target /= null и
      --  сравниваем Epoch, только затем считаем ссылку живой.
      --  Порядок проверки: (1) нулевой указатель, (2) эпоха.
      --  Разыменование Target.all происходит ТОЛЬКО после обеих проверок.
      if Self.Target = null then
         Value := null;
         Alive := False;
         return;
      end if;
      --  Читаем Epoch через Volatile-доступ (Target задекларирован
      --  как Volatile в Object_Header) — Safe-чтение без лока.
      if Self.Target.Header.Epoch /= Self.Expected_Epoch then
         Value := null;
         Alive := False;
         return;
      end if;
      Value := Self.Target;
      Alive := True;
   end Upgrade;

   function Make_Weak (Strong : Object_Access) return Instance is
   begin
      if Strong = null then
         return (Target         => null,
                 Expected_Epoch => 0);
      end if;
      return (Target         => Strong,
              Expected_Epoch => Strong.Header.Epoch);
   end Make_Weak;

   function Is_Expired (Self : Instance) return Boolean is
   begin
      if Self.Target = null then return True; end if;
      return Self.Target.Header.Epoch /= Self.Expected_Epoch;
   end Is_Expired;

end Aura.Weak_Ref;
