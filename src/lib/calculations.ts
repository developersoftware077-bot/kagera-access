import type { Product, ResearchResponse, Seller } from '../types'
export const tzs = (value: number | undefined) => `TZS ${(value ?? 0).toLocaleString('en-US')}`
export const sellerStatus = (sellerId: string, responses: ResearchResponse[], productCount: number) => {
 const count = responses.filter(r => r.sellerId === sellerId).length
 if (!count) return { label: 'Not Started', count, percent: 0 }
 return { label: count >= productCount && productCount > 0 ? 'Completed' : 'In Progress', count, percent: productCount ? Math.round(count / productCount * 100) : 0 }
}
export const analysisRows = (products: Product[], responses: ResearchResponse[]) => products.map(product => {
 const rs = responses.filter(r => r.productId === product.id); const n = rs.length || 1
 return { ...product, responseCount: rs.length, avgBuying: Math.round(rs.reduce((a,r)=>a+r.buyingPrice,0)/n), avgSelling: Math.round(rs.reduce((a,r)=>a+r.sellingPrice,0)/n), demand: rs.reduce((a,r)=>a+r.monthlyQuantity,0), oftenUnavailable: rs.filter(r=>r.availability==='often').length, interested: rs.filter(r=>r.interestedInSupplier).length }
}).sort((a,b)=>b.demand-a.demand)
export const missingInfo = (sellers: Seller[], products: Product[], responses: ResearchResponse[]) => ({ followUps: sellers.filter(s => sellerStatus(s.id, responses, products.length).label !== 'Completed').length, missingPrices: responses.filter(r => !r.buyingPrice || !r.sellingPrice).length, missingDemand: responses.filter(r => !r.monthlyQuantity).length })
