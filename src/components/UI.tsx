import type { ButtonHTMLAttributes, InputHTMLAttributes, ReactNode } from 'react'
export function Button({ children, className='', ...props }: ButtonHTMLAttributes<HTMLButtonElement>) { return <button className={`button ${className}`} {...props}>{children}</button> }
export function Input({ label, error, ...props }: InputHTMLAttributes<HTMLInputElement> & { label?: string; error?: string }) { return <label className="field">{label && <span>{label}</span>}<input {...props}/>{error && <small className="error">{error}</small>}</label> }
export function Select({ label, children, ...props }: React.SelectHTMLAttributes<HTMLSelectElement> & {label?: string, children: ReactNode}) { return <label className="field">{label && <span>{label}</span>}<select {...props}>{children}</select></label> }
export function Empty({ title, text, action }: {title:string;text:string;action?:ReactNode}) { return <div className="empty"><h3>{title}</h3><p>{text}</p>{action}</div> }
export function Loading() { return <div className="loading">Inapakia…</div> }
