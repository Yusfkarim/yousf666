-- Starter Sorani Kurdish marketplace categories. Safe to run repeatedly.
insert into public.categories (name_ku, icon_name, sort_order)
values
  ('چێشتخانە و خواردن', 'restaurant', 10),
  ('مارکێت', 'storefront', 20),
  ('مۆبایل و ئەلیکترۆنیات', 'devices', 30),
  ('جلوبەرگ', 'checkroom', 40),
  ('کەلوپەلی ناوماڵ', 'chair', 50),
  ('جوانکاری و تەندروستی', 'spa', 60),
  ('کتێب و کەلوپەلی خوێندن', 'menu_book', 70),
  ('ورزش و کات بەسەربردن', 'sports_soccer', 80),
  ('ئامراز و کەلوپەلی پیشەیی', 'handyman', 90),
  ('ئاژەڵ و پێداویستییەکانی', 'pets', 100)
on conflict (name_ku) do update
set icon_name = excluded.icon_name,
    sort_order = excluded.sort_order;
