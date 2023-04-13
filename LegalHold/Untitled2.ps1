 class ObjComparer3:System.Collections.Generic.IComparer[System.Object]
 {
     [System.Object] $x
     [System.Object] $y

     [int] Compare($x,$y) {
         return $x.Length.CompareTo($y)
     }
 }

 $comparer = [ObjComparer3]::new()
 $l1.BinarySearch("Ben", $comparer)