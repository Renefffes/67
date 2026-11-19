export type Card = { id: string; front: string; back: string; known: boolean };
export type Deck = { id: string; title: string; subject: string; color: string; notes: string; cards: Card[]; created: number };
export type StudyData = { version: 1; decks: Deck[]; answers: number; correct: number; days: string[] };
export const uid = () => crypto.randomUUID();
export const palette = ['violet', 'mint', 'peach', 'blue'];
export const sampleNotes = `Cell: The basic unit of life.
Nucleus: The control centre of the cell that stores DNA.
Mitochondria: Organelles that release energy through respiration.
Ribosomes: Tiny structures that build proteins.
Osmosis: The movement of water across a partially permeable membrane.
Photosynthesis: Plants use sunlight, water and carbon dioxide to make glucose and oxygen.
Chloroplasts: Structures in plant cells that contain chlorophyll.
Cell membrane: Controls what enters and leaves the cell.`;
export function extractCards(notes: string): Card[] {
  const lines = notes.split(/\n|(?<=[.!?])\s+/).map(s => s.replace(/^\s*[-•\d.)]+\s*/, '').trim()).filter(Boolean);
  const cards: Card[] = [];
  for (const line of lines) {
    const pair = line.match(/^(.{1,100}?)\s*(?::|\s[–—=]\s|\t)\s*(.{2,})$/);
    const sentence = line.match(/^(.{2,80}?)\s+(is|are|means|refers to|was|were)\s+(.{3,})$/i);
    const front = pair ? `What is ${pair[1].trim()}?` : sentence ? `What ${/are|were/i.test(sentence[2]) ? 'are' : 'is'} ${sentence[1].trim()}?` : `Complete: ${line.split(/\s+/).slice(0, 5).join(' ')} …`;
    const back = pair ? pair[2].trim() : sentence ? sentence[3].trim() : line;
    if (line.length > 8 && !cards.some(c => c.front === front)) cards.push({ id: uid(), front, back, known: false });
    if (cards.length === 40) break;
  }
  return cards;
}
function sample(title: string, subject: string, color: string, notes: string): Deck { return { id: uid(), title, subject, color, notes, cards: extractCards(notes), created: Date.now() }; }
export function initialData(): StudyData {
  return { version: 1, answers: 0, correct: 0, days: [], decks: [sample('The living cell', 'Biology', 'mint', sampleNotes), sample('A world in motion', 'Physics', 'blue', 'Velocity: Speed in a given direction.\nAcceleration: The rate of change of velocity.\nForce: A push or pull measured in newtons.\nInertia: The tendency of an object to resist a change in motion.\nMomentum: Mass multiplied by velocity.\nFriction: A force that opposes motion.'), sample('Everyday French', 'Languages', 'peach', 'Bonjour: Hello.\nMerci: Thank you.\nÀ bientôt: See you soon.\nUne bibliothèque: A library.\nApprendre: To learn.\nUn cahier: An exercise book.')] };
}
export function shuffle<T>(items: T[]): T[] { const a = [...items]; for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; }
export function choicesFor(card: Card, cards: Card[]): string[] { return shuffle([card.back, ...shuffle([...new Set(cards.filter(c => c.back !== card.back).map(c => c.back))]).slice(0, 3)]); }
export function relevantNotes(question: string, deck: Deck): string {
  const words = question.toLowerCase().match(/[\p{L}\p{N}]{3,}/gu)?.filter(w => !['what','does','that','this','with','have','explain','about','could','please','which','tell','from','the','and','are','how','why'].includes(w)) ?? [];
  const ranked = deck.cards.map(c => ({c, score: words.reduce((n, w) => n + (`${c.front} ${c.back}`.toLowerCase().includes(w) ? 1 : 0), 0)})).filter(r => r.score > 0).sort((a,b) => b.score-a.score).slice(0, 3);
  return ranked.map(({c}) => `${c.front}\n${c.back}`).join('\n\n');
}
export function validateData(value: unknown): value is StudyData {
  if (!value || typeof value !== 'object') return false;
  const d = value as StudyData;
  return d.version === 1 && Number.isSafeInteger(d.answers) && d.answers >= 0 && Number.isSafeInteger(d.correct) && d.correct >= 0 && d.correct <= d.answers && Array.isArray(d.days) && d.days.every(s => typeof s === 'string') && Array.isArray(d.decks) && d.decks.length <= 500 && d.decks.every(deck => deck && typeof deck.id === 'string' && typeof deck.title === 'string' && typeof deck.subject === 'string' && palette.includes(deck.color) && typeof deck.notes === 'string' && Number.isFinite(deck.created) && Array.isArray(deck.cards) && deck.cards.every(c => c && typeof c.id === 'string' && typeof c.front === 'string' && typeof c.back === 'string' && typeof c.known === 'boolean'));
}
