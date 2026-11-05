// Approved fallback challenges. Used when the AI is unavailable, returns junk, or too few candidates pass validation.
// Every entry is re-checked by checkPolicy in the test suite, so this library can never contain something the policy rejects.
import type { Category, ChallengeDraft, Difficulty, ModifierId, Theme } from './types.ts';

type F = [Category, string, string, number, Difficulty, string[], ModifierId[], Theme[]?];

const L: F[] = [
  // improvise
  ['improvise', 'Sell the Ordinary', 'Pitch a plain water bottle as a luxury invention that changes lives.', 45, 2, ['You present a clear pitch', 'The pitch is about the assigned object'], ['change_the_tone', 'add_a_required_word']],
  ['improvise', 'Three Word Saga', 'Tell a short story that uses the words lantern, accountant and thunder.', 40, 2, ['All three words appear in the story', 'The story has a beginning and an end'], ['add_a_required_word', 'rhyme']],
  ['improvise', 'Quiet Morning, Loud Thriller', 'Narrate a quiet morning routine as if it were the final scene of a suspense film.', 45, 3, ['You narrate without long silences', 'The tension builds until the final line'], ['whisper_only', 'dramatic_pause'], ['role_play']],
  ['improvise', 'Forecast From Nowhere', 'Deliver a serious weather forecast for a city that exists only in your imagination.', 40, 1, ['You name the city', 'You describe at least three weather conditions'], ['change_the_tone', 'sports_commentator']],
  ['improvise', 'The Reluctant Hero', 'Improvise a one minute speech as a hero who would much rather be napping.', 60, 3, ['You stay in the role throughout', 'You mention what the hero is saving'], ['new_character', 'third_person'], ['role_play', 'public_speaking']],
  ['improvise', 'Backwards Explainer', 'Explain how to tie a shoelace, but begin with the very last step and work back to the first.', 50, 4, ['Every step is covered', 'Steps are in reverse order'], ['slow_motion_voice', 'dramatic_pause']],
  // create
  ['create', 'Late Again Gadget', 'Invent a gadget for people who are always late, name it, and pitch it to the audience.', 60, 2, ['The gadget has a name', 'You explain how it works', 'You close with a call to action'], ['change_the_tone', 'add_a_required_word']],
  ['create', 'One Line Creature', 'Sketch an imaginary creature using one continuous line, then name it and explain its powers.', 45, 2, ['A drawing is shown to the camera', 'The creature has a name and one power'], ['sports_commentator']],
  ['create', 'Tiny Museum', 'Choose three objects near you and present them as priceless artefacts of a lost civilisation.', 60, 3, ['Three objects are shown', 'Each artefact gets a name and a story'], ['third_person', 'slow_motion_voice']],
  ['create', 'Slogan Factory', 'Create a slogan and a short advert for a product that does not exist.', 40, 2, ['The product is named', 'The slogan is clear and memorable'], ['rhyme', 'whisper_only']],
  ['create', 'Four Line Room Poem', 'Compose and recite a four line poem about the room you are sitting in.', 45, 2, ['The poem has four lines', 'It refers to something in the room'], ['rhyme', 'dramatic_pause']],
  ['create', 'Film That Never Was', 'Describe the poster, tagline and plot of a film that does not exist, inspired only by things on your desk.', 60, 3, ['You describe the poster', 'You give a tagline and a plot'], ['change_the_tone', 'sports_commentator']],
  // perform
  ['perform', 'Paper Folding Final', 'Commentate on yourself folding a piece of paper as though it were a world championship final.', 45, 2, ['You commentate continuously', 'The paper is folded on camera'], ['sports_commentator', 'whisper_only']],
  ['perform', 'Morning Villain', 'Perform a dramatic villain monologue about the injustice of early mornings.', 50, 3, ['You stay in the villain role', 'The monologue has a clear ending line'], ['new_character', 'dramatic_pause'], ['dark_humor', 'role_play', 'public_speaking']],
  ['perform', 'Breaking News: Missing Object', 'Read a breaking news report about an everyday object that has gone missing.', 45, 2, ['You report in a news style', 'You name the missing object and a theory'], ['change_the_tone', 'third_person']],
  ['perform', 'Nature Documentary', 'Narrate the next thirty seconds of your own life in the voice of a nature documentary.', 40, 2, ['You narrate your actions live', 'Your voice stays calm and reverent'], ['whisper_only', 'slow_motion_voice']],
  ['perform', 'Sock Court', 'Deliver a closing argument defending a sock that has lost its partner.', 50, 3, ['You address the jury', 'You give at least two reasons'], ['rhyme', 'sports_commentator'], ['public_speaking']],
  ['perform', 'Aria of Errands', 'Perform your to do list as a dramatic operatic aria.', 45, 4, ['At least three tasks are performed', 'You commit to the drama'], ['slow_motion_voice', 'dramatic_pause'], ['singing']],
  // solve
  ['solve', 'Sevens Backwards', 'Count backwards from one hundred in steps of seven for as long as you can without a mistake.', 40, 3, ['You count aloud', 'You reach at least fifty'], [], ['trivia_pressure']],
  ['solve', 'Animal Rush', 'Name as many animals starting with the letter S as you can before time runs out.', 30, 1, ['At least eight animals are named', 'No animal is repeated'], [], ['trivia_pressure']],
  ['solve', 'Alphabet Reversal', 'Recite the alphabet backwards from Z without stopping.', 30, 2, ['You finish at A', 'You make no more than two errors'], ['slow_motion_voice'], ['trivia_pressure']],
  ['solve', 'Letter Categories', 'For each letter from A to F, say one country, one animal and one colour.', 60, 3, ['All six letters are covered', 'Each letter has three answers'], [], ['trivia_pressure']],
  ['solve', 'Mental Math Duo', 'Multiply thirteen by fourteen, then seventeen by six, aloud and without a calculator.', 30, 2, ['Both answers are given', 'Both answers are correct'], [], ['trivia_pressure']],
  ['solve', 'Five Item Memory', 'Study the room for ten seconds, turn away, and name five objects you saw.', 40, 3, ['Five objects are named', 'The objects really are in the room'], [], ['trivia_pressure']],
  // social courage
  ['social_courage', 'Elevator Introduction', 'Introduce yourself to the camera as if meeting a respected mentor, in thirty seconds, with steady eye contact.', 40, 1, ['You state your name and one interest', 'You keep eye contact with the camera'], ['change_the_tone'], ['role_play']],
  ['social_courage', 'Compliment Round', 'Give three sincere compliments to the audience, each about a different thing visible on screen.', 45, 2, ['Three compliments are given', 'Each one is kind and specific'], ['whisper_only', 'third_person']],
  ['social_courage', 'Confident Toast', 'Give a two sentence toast to the audience as if they had just won something together.', 30, 2, ['The toast has two sentences', 'It sounds warm and confident'], ['rhyme', 'dramatic_pause'], ['public_speaking']],
  ['social_courage', 'Apology to an Object', 'Make a heartfelt and over the top apology to an object you have neglected.', 45, 2, ['You name the object', 'You give a specific reason for the apology'], ['third_person', 'slow_motion_voice'], ['role_play']],
  ['social_courage', 'Fan Society Welcome', 'Give an enthusiastic welcome speech to new members of a fan society for your favourite household object.', 50, 3, ['You welcome the new members', 'You give two reasons to join'], ['change_the_tone', 'sports_commentator'], ['public_speaking']],
  ['social_courage', 'Bold First Sentence', 'Open a presentation with a bold first sentence about a topic made from three words you spot around you.', 45, 4, ['Three words are chosen aloud', 'The opening sentence is confident and clear'], ['dramatic_pause', 'whisper_only'], ['public_speaking']],
  // easy warm-ups (difficulty 1) so that a low difficulty ceiling still yields five different options
  ['improvise', 'Cloud Review', 'Review an imaginary cloud like a luxury hotel, giving it stars and one polite complaint.', 35, 1, ['You give a star rating', 'You mention one complaint'], ['change_the_tone', 'third_person']],
  ['improvise', 'Greetings From Mars', 'Greet the audience as an alien ambassador visiting for the very first time.', 30, 1, ['You greet the audience', 'You mention one thing about our planet'], ['whisper_only', 'rhyme']],
  ['create', 'Grand New Name', 'Give an ordinary object near you a grand new name and explain why it deserves it.', 30, 1, ['The object is shown', 'The new name is explained'], ['rhyme', 'third_person']],
  ['create', 'Silly Slogan', 'Invent a slogan for your favourite spoon and say it three times with growing confidence.', 30, 1, ['The slogan is clear', 'Confidence grows with each repeat'], ['whisper_only', 'dramatic_pause']],
  ['perform', 'Calm Announcer', 'Announce the arrival of an imaginary airship in a calm and very official voice.', 30, 1, ['You sound official', 'You give a time and a gate'], ['slow_motion_voice', 'sports_commentator']],
  ['perform', 'Grand Prize Reveal', 'Reveal an object from your desk as if it were the grand prize on a game show.', 30, 1, ['You build suspense', 'You reveal the object with flair'], ['dramatic_pause', 'sports_commentator']],
  ['solve', 'Colour Chain', 'Name ten things that are red as quickly as you can.', 30, 1, ['Ten different things are named', 'No item is repeated'], [], ['trivia_pressure']],
  ['solve', 'Count By Twos', 'Count from zero to forty in steps of two without hesitating.', 25, 1, ['You reach forty', 'You do not stop between numbers'], [], ['trivia_pressure']],
  ['social_courage', 'Warm Hello', 'Greet the audience warmly three different ways, each with a different energy.', 30, 1, ['Three greetings are given', 'Each has a clearly different energy'], ['whisper_only', 'change_the_tone']],
  ['social_courage', 'Gratitude Round', 'Thank the audience for being here and name one thing you appreciate about today.', 30, 1, ['You thank the audience', 'You name something specific'], ['dramatic_pause']],
  // hard finishers (difficulty 5)
  ['improvise', 'Alphabet Saga', 'Tell a one minute story where each sentence begins with the next letter of the alphabet, starting from A.', 60, 5, ['At least eight sentences', 'Each sentence uses the next letter in order'], ['rhyme', 'third_person']],
  ['create', 'Double Duty Invention', 'Design, name and pitch a fictional invention that solves two unrelated problems at once.', 90, 5, ['The invention has a name', 'Both problems are solved convincingly', 'The pitch ends with a strong close'], ['change_the_tone', 'sports_commentator']],
  ['perform', 'Genre Roulette', 'Retell a fairy tale in three different genres, thirty seconds each, switching without a pause.', 90, 5, ['Three genres are used', 'The story stays recognisable'], ['new_character', 'slow_motion_voice'], ['role_play']],
  ['solve', 'Reverse Chain', 'Spell your first name backwards, then the word telescope backwards, then count down from twenty in threes.', 45, 5, ['All three parts are completed', 'Mistakes are corrected quickly'], [], ['trivia_pressure']],
  ['social_courage', 'Impromptu Keynote', 'Make a bold claim about something you can see, support it with three points, and end on a memorable line.', 90, 5, ['A bold claim is made', 'Three supporting points are given', 'The last line lands'], ['dramatic_pause', 'whisper_only'], ['public_speaking']],
];

export const FALLBACK_DRAFTS: ChallengeDraft[] = L.map(([category, title, objective, durationSeconds, difficulty, completionCriteria, allowedModifiers, tags]) => ({
  category, title, objective, durationSeconds, difficulty, completionCriteria, allowedModifiers,
  scoringType: category === 'solve' ? 'objective_check' : 'audience_judgment',
  tags: tags ?? [],
}));
