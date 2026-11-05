// Development-only demo clips so the Feed is alive before real recording is configured.
// They are the five short videos in server/public/demo (served at /demo, with a poster frame each) and are labelled DEMO in the app:
// they are NOT real dares. The authors are made-up handles with no account behind them.
import type { Repo } from './store/types.ts';

interface Demo { file: string; title: string; category: string; avatar: string; handle: string; caption: string; difficulty: number; twist?: string; likes: number }

const DEMOS: Demo[] = [
  { file: 'dino', title: 'Dino Shopping Run', category: 'improvise', avatar: 'a06', handle: 'rex_aisle_five', caption: 'Aisle five was not ready.', difficulty: 2, twist: 'new_character', likes: 38 },
  { file: 'karaoke', title: 'Karaoke Solo', category: 'perform', avatar: 'a09', handle: 'kira_sings', caption: 'Sang like nobody was watching. Everybody was.', difficulty: 2, twist: 'dramatic_pause', likes: 31 },
  { file: 'splash', title: 'Surprise Splash', category: 'perform', avatar: 'a02', handle: 'sam_soaked', caption: 'The crowd voted. He never saw it coming.', difficulty: 2, likes: 26 },
  { file: 'fountain', title: 'Fountain Walk', category: 'perform', avatar: 'a04', handle: 'fountain_finn', caption: 'Shoes on. Zero regrets.', difficulty: 3, likes: 19 },
  { file: 'slackline', title: 'Slackline Steps', category: 'perform', avatar: 'a03', handle: 'lena_on_the_line', caption: 'Five steps. A lot of wobble.', difficulty: 3, likes: 14 },
];

export async function seedDemoClips(repo: Repo): Promise<number> {
  let n = 0;
  for (const demo of DEMOS) {
    const clip = await repo.createClip({
      authorId: `demo-${demo.handle}`, authorHandle: demo.handle, authorAvatar: demo.avatar, title: demo.title, category: demo.category,
      difficulty: demo.difficulty, twist: demo.twist ?? null, durationMs: 4000,
      // A path starting with "url:" is served as-is. This one is relative to the server and made absolute per request (see feedItem).
      storagePath: `url:/demo/dare-${demo.file}.mp4`, status: 'published', caption: demo.caption,
    });
    for (let k = 0; k < demo.likes; k++) { await repo.setLike(clip.id, `demo-fan-${k}`, true); await repo.recordView(clip.id, `demo-fan-${k}`); }
    n++;
  }
  return n;
}
