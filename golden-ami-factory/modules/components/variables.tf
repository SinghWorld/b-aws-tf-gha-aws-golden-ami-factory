variable "name_prefix" {
  description = "Prefix applied to component names."
  type        = string
}

variable "tags" {
  description = "Tags applied to components."
  type        = map(string)
  default     = {}
}
