with ranked_segments as (
  select
    id,
    row_number() over (
      partition by reel_id, order_index
      order by created_at desc nulls last, id desc
    ) as row_number
  from public.reel_segments
)
delete from public.reel_segments
using ranked_segments
where public.reel_segments.id = ranked_segments.id
  and ranked_segments.row_number > 1;

create unique index if not exists reel_segments_reel_id_order_index_key
on public.reel_segments (reel_id, order_index);
