// main.mbt
// --- 常量和全局数据结构 ---
priv type Grid[T] FixedArray[T]

///|
fn[T] Grid::new(val : T) -> Grid[T] {
  FixedArray::make(81, val)
}

///|
fn[T] Grid::copy(self : Grid[T]) -> Grid[T] {
  let arr = FixedArray::make(81, self.inner()[0])
  let mut i = 0
  while i < 81 {
    arr[i] = self.inner()[i]
    i = i + 1
  }
  return arr
}

let rows = "ABCDEFGHI"
let cols = "123456789"

// square_to_int 函数：将数独方格坐标（例如 "A1"）转换为整数索引（0-80）
// 如果输入无效，则调用 abort 终止程序
fn square_to_int(square : String) -> Int {
  let row_char = square.char_at(0)
  let col_char = square.char_at(1)
  
  // Find row index (A=0, B=1, ..., I=8)
  let mut row_idx = -1
  let mut i = 0
  while i < rows.length() {
    if rows.char_at(i) == row_char {
      row_idx = i
      break
    }
    i = i + 1
  }
  
  // Find col index (1=0, 2=1, ..., 9=8)
  let mut col_idx = -1
  i = 0
  while i < cols.length() {
    if cols.char_at(i) == col_char {
      col_idx = i
      break
    }
    i = i + 1
  }
  
  if row_idx == -1 || col_idx == -1 {
    abort("Invalid square coordinate: \{square}")
  }
  
  row_idx * 9 + col_idx
}


///|
fn[T] Grid::op_get(self : Grid[T], square : String) -> T {
  let i = square_to_int(square)
  self.inner()[i]
}

///|
fn[T] Grid::op_set(self : Grid[T], square : String, x : T) -> Unit {
  let i = square_to_int(square)
  self.inner()[i] = x
}


// --- 预计算的数独结构 ---

typealias @immut/sorted_set.T[String] as Squares

// squares 包含每个方格的坐标
let squares : Squares = (fn () {
  let mut result = @immut/sorted_set.new()
  for row in rows {
    for col in cols {
      result = result.add("\{row}\{col}")
    }
  }
  result
})()

// unitlist 是所有27个单元（9行，9列，9个3x3方块）的列表
let unitlist : Array[Squares] = (fn () {
  let list = Array::make(27, @immut/sorted_set.new())
  let mut i = 0
  // 行单元
  for r in rows {
    let mut row_unit = @immut/sorted_set.new()
    for c in cols {
      row_unit = row_unit.add("\{r}\{c}")
    }
    list[i] = row_unit
    i = i + 1
  }
  // 列单元
  for c in cols {
    let mut col_unit = @immut/sorted_set.new()
    for r in rows {
      col_unit = col_unit.add("\{r}\{c}")
    }
    list[i] = col_unit
    i = i + 1
  }
  // 3x3方块单元
  let box_rows = ["ABC", "DEF", "GHI"]
  let box_cols = ["123", "456", "789"]
  for rs in box_rows {
    for cs in box_cols {
      let mut box_unit = @immut/sorted_set.new()
      for r in rs {
        for c in cs {
          box_unit = box_unit.add("\{r}\{c}")
        }
      }
      list[i] = box_unit
      i = i + 1
    }
  }
  list
})()

// units[square] 包含该方格所属的3个单元（行、列、方块）
let units : Grid[Array[Squares]] = (fn () {
  let result = Grid::new(Array::make(0, @immut/sorted_set.new())) // Placeholder
  for s in squares {
    let s_units = Array::make(3, @immut/sorted_set.new())
    let mut count = 0
    for unit in unitlist {
      if unit.contains(s) {
        s_units[count] = unit
        count = count + 1
      }
    }
    result[s] = s_units
  }
  result
})()

// peers[square] 包含与该方格共享一个单元的所有其他方格（共20个）
let peers : Grid[Squares] = (fn () {
  let result = Grid::new(@immut/sorted_set.new())
  for s in squares {
    let mut peer_set = @immut/sorted_set.new()
    for unit in units[s] {
      for square_in_unit in unit {
        if square_in_unit != s {
          peer_set = peer_set.add(square_in_unit)
        }
      }
    }
    result[s] = peer_set
  }
  result
})()

// --- 数独求解器核心函数 ---

// 函数必须在使用前定义，特别是对于相互递归的函数。
// 顺序: assign -> eliminate -> parse -> search -> solve

fn assign(values : Grid[@immut/sorted_set.T[Char]], key : String, val : Char) -> Bool {
  // 获取除了 val 之外的其他所有可能值
  let other_values = values[key].remove(val)
  let mut all_ok = true
  // 依次从 key 中消除其他所有值
  for other_val in other_values {
    if not(eliminate(values, key, other_val)) {
      all_ok = false
      break
    }
  }
  return all_ok
}

// eliminate 函数：从方格的可能值中移除一个数字，并传播约束
// 如果成功返回 true，如果发现矛盾返回 false
fn eliminate(
  values : Grid[@immut/sorted_set.T[Char]],
  key : String,
  val : Char
) -> Bool {
  // 1. 如果 val 已经不在 values[key] 中，直接返回 true
  if not(values[key].contains(val)) {
    return true
  }

  // 2. 从 values[key] 中移除 val
  values[key] = values[key].remove(val)

  // 3. 检查矛盾或传播
  match values[key].size() {
    0 => {
      // 矛盾：移除了最后一个值
      return false
    }
    1 => {
      // 传播规则1：如果一个方格只剩下一个值，从其所有 peers 中移除该值
      let last_val = values[key].min()
      let mut all_ok = true
      for peer_key in peers[key] {
        if not(eliminate(values, peer_key, last_val)) {
          all_ok = false
          break
        }
      }
      if not(all_ok) {
        return false
      }
    }
    _ => ()
  }

  // 4. 传播规则2：如果一个单元对于某个值只有一个可能的位置，则将该值赋给该位置
  for unit in units[key] {
    let places_for_val = Array::new()
    for sq in unit {
      if values[sq].contains(val) {
        places_for_val.push(sq)
      }
    }

    match places_for_val.length() {
      0 => {
        // 矛盾：在这个单元中，val 无处可放
        return false
      }
      1 => {
        // 只有一个位置，必须赋值
        if not(assign(values, places_for_val[0], val)) {
          return false
        }
      }
      _ => () // 大于一个位置，继续
    }
  }

  return true
}

// Grid::format 函数：格式化输出数独网格
fn Grid::format(self : Grid[@immut/sorted_set.T[Char]]) -> String {
  let mut result = ""
  for r_idx = 0; r_idx < 9; r_idx = r_idx + 1 {
    if r_idx > 0 && r_idx % 3 == 0 {
      result = result + "---------+---------+---------\n"
    }
    for c_idx = 0; c_idx < 9; c_idx = c_idx + 1 {
      if c_idx > 0 && c_idx % 3 == 0 {
        result = result + "| "
      }
      let square = "\{rows.char_at(r_idx)}\{cols.char_at(c_idx)}"
      let val_set = self[square]
      if val_set.size() == 1 {
        result = result + val_set.min().to_string() + " "
      } else {
        result = result + ". "
      }
    }
    if r_idx < 8 {
      result = result + "\n"
    }
  }
  result
}


// Grid::parse 函数：将输入的数独字符串解析为初始的 Grid 状态
fn Grid::parse(s : String) -> Grid[@immut/sorted_set.T[Char]]? {
  let digits = @immut/sorted_set.from_array(cols.to_array())
  let values = Grid::new(digits)
  
  // 确保字符串长度为81
  if s.length() != 81 {
      return None
  }

  let mut i = 0
  for square in squares {
    let c = s.char_at(i)
    if cols.contains(c.to_string()) {
      if not(assign(values, square, c)) {
        return None // 如果初始赋值就产生矛盾，则无解
      }
    }
    i = i + 1
  }
  Some(values)
}


// search 函数：使用递归回溯算法进行深度优先搜索
// 如果找到解决方案，返回 Some(已解决的网格)，否则返回 None
fn search(
  values : Grid[@immut/sorted_set.T[Char]]
) -> Grid[@immut/sorted_set.T[Char]]? {
    // 检查是否所有方格都已确定
    let mut is_solved = true
    for sq in squares {
        if values[sq].size() != 1 {
            is_solved = false
            break
        }
    }
    if is_solved {
        return Some(values) // 解决！
    }

    // 寻找可能性最少的未确定方格 (Minimum Remaining Values heuristic)
    let mut min_sq = ""
    let mut min_len = 10
    for sq in squares {
        let len = values[sq].size()
        if len > 1 && len < min_len {
            min_len = len
            min_sq = sq
        }
    }

    // 对该方格的每种可能性进行递归尝试
    for digit in values[min_sq] {
        let next_values = values.copy()
        if assign(next_values, min_sq, digit) {
            let result = search(next_values)
            match result {
                Some(solved_grid) => {
                    return Some(solved_grid) // 找到解，返回
                }
                None => {
                    // 此路不通，继续尝试下一个数字
                    continue
                }
            }
        }
    }

    // 如果所有可能性都尝试失败，说明此路不通，回溯
    return None
}

// solve 函数：整合解析和搜索过程
fn solve(g : String) -> String {
  // 清理输入字符串，只保留数字和点
  let clean_g_buf = @buffer.new() // 使用缓冲区进行高效清理
  for char in g {
    // 优化：使用 Char 算术进行数字检查
    let is_digit = char.to_int() >= '1'.to_int() && char.to_int() <= '9'.to_int()
    if is_digit || char == '.' || char == '0' {
      clean_g_buf.write_char(char) // 直接将字符写入缓冲区
    }
  }
  let clean_g = clean_g_buf.to_string() // 将缓冲区内容转换为 String

  match Grid::parse(clean_g) {
    None => "Error: Initial grid is invalid or has a contradiction."
    Some(initial_grid) => {
      match search(initial_grid) {
        None => "can't solve this puzzle"
        Some(v) => v.format()
      }
    }
  }
}


// --- 示例用法 (main 函数用于执行) ---
// --- 示例用法 (main 函数用于执行) ---

// Test Cases Categories:
// (a) 简单谜题（空单元格少，快速求解）
// (b) 中等/困难谜题（空单元格多，需要更多回溯）
// (c) 无解谜题（初始状态矛盾或无法求解）
// (d) 已解决的谜题
// (e) 无效输入字符串（例如，长度不正确、非数字/非点字符）

// (a) 简单谜题
let easy_grid = "003020600900305001001806400008102900700000008006708200002609500800203009005010300"
let easy_solution : String =
    "4 8 3 | 9 2 1 | 6 5 7\n" +
    "9 6 7 | 3 4 5 | 8 2 1\n" +
    "2 5 1 | 8 7 6 | 4 9 3\n" +
    "---------+---------+---------\n" +
    "5 4 8 | 1 3 2 | 9 7 6\n" +
    "7 2 9 | 5 8 6 | 4 3 2\n" +
    "1 3 6 | 7 9 8 | 2 4 5\n" +
    "---------+---------+---------\n" +
    "3 7 2 | 6 8 9 | 5 1 4\n" +
    "8 1 4 | 2 5 3 | 7 6 9\n" +
    "6 9 5 | 4 1 7 | 3 8 2"

test "Easy Sudoku Puzzle" {
    let solution = solve(easy_grid)
    let mut clean_solution = ""
    for char in solution {
        if char != ' ' && char != '\n' && char != '|' && char != '-' && char != '+' {
            clean_solution = clean_solution + char.to_string()
        }
    }
    let mut clean_expected = ""
    for char in easy_solution {
        if char != ' ' && char != '\n' && char != '|' && char != '-' && char != '+' {
            clean_expected = clean_expected + char.to_string()
        }
    }
    inspect(clean_solution, content=clean_expected)
}

// (b) 中等/困难谜题 (from the original problem, often considered medium/hard)
let grid1 =
  "4.....8.5.3..........7......2.....6.....8.4......1.......6.3.7.5..2.....1.4......"

let expected_solution : String =
    "4 1 7 | 3 6 9 | 8 2 5\n" +
    "6 3 2 | 1 5 8 | 9 4 7\n" +
    "9 5 8 | 7 2 4 | 3 1 6\n" +
    "---------+---------+---------\n" +
    "8 2 5 | 4 3 7 | 1 6 9\n" +
    "7 9 1 | 5 8 6 | 4 3 2\n" +
    "3 4 6 | 9 1 2 | 7 5 8\n" +
    "---------+---------+---------\n" +
    "2 8 9 | 6 4 3 | 5 7 1\n" +
    "5 7 3 | 2 9 1 | 6 8 4\n" +
    "1 6 4 | 8 7 5 | 2 9 3"

test "Medium/Hard Sudoku Puzzle (Original)" {
  let solution = solve(grid1)
  let mut clean_solution = ""
  for char in solution {
      if char != ' ' && char != '\n' && char != '|' && char != '-' && char != '+' {
          clean_solution = clean_solution + char.to_string()
      }
  }
  let mut clean_expected = ""
  for char in expected_solution {
      if char != ' ' && char != '\n' && char != '|' && char != '-' && char != '+' {
          clean_expected = clean_expected + char.to_string()
        }
  }
  inspect(clean_solution, content=clean_expected)
}

// (b) 另一个困难谜题 (from a common list of hard sudokus, e.g., "AI Escargot")
let hard_grid_known = "8..........36......7..9.2...5...7.......45....7..8...6.3.54...3..8.87....1.4.2"
let hard_solution_known :String=
    "8 1 2 | 7 5 3 | 6 4 9\n" +
    "9 4 3 | 6 8 2 | 1 7 5\n" +
    "6 7 5 | 4 9 1 | 2 8 3\n" +
    "---------+---------+---------\n" +
    "1 5 4 | 2 3 7 | 8 9 6\n" +
    "3 6 9 | 8 4 5 | 7 2 1\n" +
    "2 8 7 | 1 6 9 | 5 3 4\n" +
    "---------+---------+---------\n" +
    "5 2 1 | 3 7 8 | 4 6 9\n" +
    "4 3 8 | 9 1 6 | 5 7 2\n" +
    "7 9 6 | 5 2 4 | 3 1 8"

test "Hard Sudoku Puzzle (Known)" {
    let solution = solve(hard_grid_known)
    let mut clean_solution = ""
    for char in solution {
        if char != ' ' && char != '\n' && char != '|' && char != '-' && char != '+' {
            clean_solution = clean_solution + char.to_string()
        }
    }
    let mut clean_expected = ""
    for char in hard_solution_known {
        if char != ' ' && char != '\n' && char != '|' && char != '-' && char != '+' {
            clean_expected = clean_expected + char.to_string()
        }
    }
    inspect(clean_solution, content=clean_expected)
}


// (c) 无解谜题 (contradiction at start)
let unsolvable_grid_contradiction = "44..............................................................................." // Two 4s in A1 and A2, will lead to early contradiction
test "Unsolvable Sudoku Puzzle (Initial Contradiction)" {
    let solution = solve(unsolvable_grid_contradiction)
    inspect(solution, content="Error: Initial grid is invalid or has a contradiction.")
}

// (c) 无解谜题 (verified contradiction by filling multiple values in same unit)
let unsolvable_grid_verified = "123456789123456789123456789123456789123456789123456789123456789123456789123456789" // All rows are 123456789, which is a contradiction.
test "Unsolvable Sudoku Puzzle (Verified Contradiction)" {
    let solution = solve(unsolvable_grid_verified)
    inspect(solution, content="Error: Initial grid is invalid or has a contradiction.")
}


// (d) 已解决的谜题
let solved_grid =
    "417369825632158947958724316825437169791586432346912758289643571573291684164875293"
let solved_solution :String=
    "4 1 7 | 3 6 9 | 8 2 5\n" +
    "6 3 2 | 1 5 8 | 9 4 7\n" +
    "9 5 8 | 7 2 4 | 3 1 6\n" +
    "---------+---------+---------\n" +
    "8 2 5 | 4 3 7 | 1 6 9\n" +
    "7 9 1 | 5 8 6 | 4 3 2\n" +
    "3 4 6 | 9 1 2 | 7 5 8\n" +
    "---------+---------+---------\n" +
    "2 8 9 | 6 4 3 | 5 7 1\n" +
    "5 7 3 | 2 9 1 | 6 8 4\n" +
    "1 6 4 | 8 7 5 | 2 9 3"

test "Already Solved Sudoku Puzzle" {
    let solution = solve(solved_grid)
    let mut clean_solution = ""
    for char in solution {
        if char != ' ' && char != '\n' && char != '|' && char != '-' && char != '+' {
            clean_solution = clean_solution + char.to_string()
        }
    }
    let mut clean_expected = ""
    for char in solved_solution {
        if char != ' ' && char != '\n' && char != '|' && char != '-' && char != '+' {
            clean_expected = clean_expected + char.to_string()
        }
    }
    inspect(clean_solution, content=clean_expected)
}

// (e) 无效输入字符串
let invalid_length_grid = "123" // Too short
test "Invalid Input Length" {
    let solution = solve(invalid_length_grid)
    inspect(solution, content="Error: Initial grid is invalid or has a contradiction.")
}

let invalid_char_grid = "12345678912345678912345678912345678912345678912345678912345678912345678912345678X" // 'X' is invalid
test "Invalid Input Character" {
    let solution = solve(invalid_char_grid)
    inspect(solution, content="Error: Initial grid is invalid or has a contradiction.")
}

fn main {
  let grid_to_solve = grid1
  println("Solving Sudoku Puzzle:")
  println(grid_to_solve)

  let solution = solve(grid_to_solve)
  println("\nSolution:")
  println(solution)
}



