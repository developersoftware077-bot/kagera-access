import { addDoc, collection, doc, getDoc, getDocs, query, serverTimestamp, setDoc, updateDoc, where } from 'firebase/firestore'
import { db } from './config'
import type { Product, QuestionnaireSession, ResearchResponse, Seller } from '../types'
const needDb = () => { if (!db) throw new Error('Firebase haijaunganishwa. Weka vigezo vya .env.') ; return db }
const docs = <T>(s: Awaited<ReturnType<typeof getDocs>>) => s.docs.map(d => ({ id: d.id, ...(d.data() as Record<string, unknown>) } as T))
export const listSellers = async () => docs<Seller>(await getDocs(collection(needDb(), 'sellers')))
export const listProducts = async () => docs<Product>(await getDocs(collection(needDb(), 'products')))
export const listResponses = async () => docs<ResearchResponse>(await getDocs(collection(needDb(), 'researchResponses')))
export async function createSeller(data: Omit<Seller, 'id'|'createdAt'>) { return (await addDoc(collection(needDb(), 'sellers'), { ...data, createdAt: serverTimestamp() })).id }
export async function createProduct(data: Omit<Product, 'id'|'createdAt'|'normalizedName'>) {
  const normalizedName = data.name.trim().toLocaleLowerCase()
  const duplicate = await getDocs(query(collection(needDb(), 'products'), where('normalizedName', '==', normalizedName)))
  if (!duplicate.empty) throw new Error('Bidhaa yenye jina hili tayari ipo.')
  return (await addDoc(collection(needDb(), 'products'), { ...data, normalizedName, createdAt: serverTimestamp() })).id
}
export async function saveResponse(data: Omit<ResearchResponse, 'id'|'createdAt'>) { return (await addDoc(collection(needDb(), 'researchResponses'), { ...data, createdAt: serverTimestamp() })).id }
export async function createQuestionnaire(productIds: string[], productSnapshots: QuestionnaireSession['productSnapshots']) { return (await addDoc(collection(needDb(), 'questionnaireSessions'), { active: true, productIds, productSnapshots, createdAt: serverTimestamp() })).id }
export async function getSession(token: string) { const snap = await getDoc(doc(needDb(), 'questionnaireSessions', token)); return snap.exists() ? ({ id: snap.id, ...snap.data() } as QuestionnaireSession) : null }
export async function publicSaveSeller(token: string, sellerId: string, data: Omit<Seller, 'id'|'createdAt'>) { await setDoc(doc(needDb(), 'sellers', sellerId), { ...data, questionnaireToken: token, createdAt: serverTimestamp() }) }
export async function publicSaveResponse(token: string, responseId: string, data: Omit<ResearchResponse, 'id'|'createdAt'>) { await setDoc(doc(needDb(), 'researchResponses', responseId), { ...data, questionnaireToken: token, createdAt: serverTimestamp() }) }
export async function setSessionProducts(sessionId: string, productIds: string[], productSnapshots: QuestionnaireSession['productSnapshots']) { await updateDoc(doc(needDb(), 'questionnaireSessions', sessionId), { productIds, productSnapshots }) }
