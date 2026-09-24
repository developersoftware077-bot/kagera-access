import { supabase } from './config'

export type CatalogueModel = {
  id: string
  brand: string
  model: string
}

export type CatalogueProduct = {
  id: string
  category: string
  name: string
  models: CatalogueModel[]
  testPrice?: number
}

/**
 * Source for the future seller questionnaire. A general accessory has an empty
 * models array; the UI should present it as Generic / N/A and allow selection.
 */
export async function listActiveCatalogue(): Promise<CatalogueProduct[]> {
  if (!supabase) throw new Error('Supabase haijaunganishwa.')
  const { data, error } = await supabase.rpc('get_active_catalogue')
  if (error) throw new Error(error.message)
  const products = new Map<string, CatalogueProduct>()
  for (const row of data ?? []) {
    let product = products.get(row.product_id)
    if (!product) {
      product = { id: row.product_id, category: row.category, name: row.product_name, models: [], testPrice: row.test_price == null ? undefined : Number(row.test_price) }
      products.set(row.product_id, product)
    }
    if (row.product_model_id) product.models.push({ id: row.product_model_id, brand: row.brand, model: row.phone_model })
  }
  return [...products.values()]
}

export async function getPublicCatalogue(token: string): Promise<CatalogueProduct[]> {
  if (!supabase) throw new Error('Supabase haijaunganishwa.')
  const { data, error } = await supabase.rpc('get_public_active_catalogue', { p_token: token })
  if (error) throw new Error(error.message)
  const products = new Map<string, CatalogueProduct>()
  for (const row of data ?? []) {
    let product = products.get(row.product_id)
    if (!product) { product = { id: row.product_id, category: row.category, name: row.product_name, models: [], testPrice: row.test_price == null ? undefined : Number(row.test_price) }; products.set(row.product_id, product) }
    if (row.product_model_id) product.models.push({ id: row.product_model_id, brand: row.brand, model: row.phone_model })
  }
  return [...products.values()]
}
