export type SellerStatus = 'Not Started' | 'In Progress' | 'Completed'
export type Availability = 'available' | 'sometimes' | 'often'
export interface Seller { id: string; shopName: string; sellerName: string; phone: string; location: string; businessType: string; createdAt?: unknown; questionnaireToken?: string }
export interface Product { id: string; name: string; category: string; phoneModel: string; notes: string; normalizedName: string; createdAt?: unknown }
export interface ResearchResponse { id: string; sellerId: string; productId: string; buyingPrice: number; sellingPrice: number; monthlyQuantity: number; availability: Availability; interestedInSupplier: boolean; initialQuantity?: number; notes?: string; createdAt?: unknown }
export interface QuestionnaireSession { id: string; active: boolean; productIds: string[]; productSnapshots?: Array<Pick<Product, 'id'|'name'|'category'>>; createdAt?: unknown }
