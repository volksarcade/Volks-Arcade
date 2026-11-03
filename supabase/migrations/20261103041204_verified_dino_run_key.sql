alter table public.verified_arcade_runs drop constraint if exists verified_arcade_runs_game_key_check;
alter table public.verified_arcade_runs add constraint verified_arcade_runs_game_key_check
check (game_key = any (array['noughts','ladders','tetris','checkers','chess','dino']::text[]));