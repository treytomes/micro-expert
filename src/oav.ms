// oav.ms — Object-Attribute-Value triplets, for describing what a thing is like.
//
//   import "oav"
//   t = oav.OavTriple.make("gluten", "contains", "gliadin")
//   print t.text                 // gluten | contains | gliadin
//   print t.parts                // ["gluten", "contains", "gliadin"]

OavTriple = {}

OavTriple.make = function(object, attribute, value)
	"Builds a triplet from its object, attribute, and value."
	t = new OavTriple
	t.object = object
	t.attribute = attribute
	t.value = value
	return t
end function

OavTriple.text = function
	"Formats the triplet as 'object | attribute | value'."
	return self.parts.join(" | ")
end function

OavTriple.parts = function
	"Returns the triplet as the list [object, attribute, value]."
	return [self.object, self.attribute, self.value]
end function
