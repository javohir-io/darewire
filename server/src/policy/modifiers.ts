// THE TWIST: approved modifier templates only. The AI never writes twists.
import type { Boundaries, Challenge, Modifier, ModifierId, Theme } from './types.ts';

interface Template { text: string; tags: Theme[] }

const WORDS = ['umbrella', 'lighthouse', 'velvet', 'compass', 'avalanche', 'marble', 'telescope', 'orchestra'];

export const MODIFIER_TEMPLATES: Record<ModifierId, Template> = {
  change_the_tone: { text: 'Switch to the exact opposite mood of what you were doing.', tags: [] },
  add_a_required_word: { text: 'Work the word "{word}" into your very next sentence.', tags: [] },
  whisper_only: { text: 'Whisper everything from this moment on.', tags: [] },
  third_person: { text: 'Speak about yourself in the third person from now on.', tags: [] },
  rhyme: { text: 'Make your next three sentences rhyme.', tags: [] },
  new_character: { text: 'Become a nervous tour guide for the rest of the round.', tags: ['role_play'] },
  slow_motion_voice: { text: 'Speak as slowly and dramatically as you possibly can.', tags: [] },
  dramatic_pause: { text: 'Add a long dramatic pause after every sentence.', tags: [] },
  sports_commentator: { text: 'Narrate your own words like a sports commentator.', tags: [] },
};

/** Up to `n` compatible twists for this challenge: allowed by the challenge, not excluded by the Player's boundaries. */
export function buildTwistOptions(c: Challenge, b: Boundaries, rng: () => number, n = 3): Modifier[] {
  const ok = c.allowedModifiers.filter((id) => MODIFIER_TEMPLATES[id].tags.every((t) => !b.excludedThemes.includes(t)));
  const pool = [...ok];
  for (let i = pool.length - 1; i > 0; i--) { const j = Math.floor(rng() * (i + 1)); [pool[i], pool[j]] = [pool[j]!, pool[i]!]; }
  return pool.slice(0, n).map((id) => ({
    id,
    text: MODIFIER_TEMPLATES[id].text.replace('{word}', WORDS[Math.floor(rng() * WORDS.length)]!),
  }));
}
